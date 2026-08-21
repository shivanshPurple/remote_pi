import 'dart:async';

import 'package:app/data/local/room_activity_store.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/epk_encoding.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:app/ui/home/states/home_state.dart';

/// HomeViewModel — passive list of paired peers + live presence dots
/// + rooms discovered on each peer (plan 17). A single tile per
/// (peer, room).
///
/// The WS connection is owned by [ConnectionManager] from app boot (plano
/// 12). Home only:
///   - reads the peer list from storage
///   - watches `presenceStream` + `roomsStream` to render dots / rooms
///     in real time
///   - writes [Preferences.selectedRoom] when the user taps a tile so
///     `/chat` knows which (peer, room) to address
///
/// Home revamp — the old All/Online/Offline tabs are gone. The page now
/// renders [liveItems] flat and folds [offlineItems] under an accordion;
/// both lists are ordered last-used-first (recency of open), with rooms
/// whose agent is mid-turn pinned to the very top. Finished turns that
/// landed while another chat was open bump the tile's unread badge via
/// [RoomActivityStore].
class HomeViewModel extends ViewModel<HomeState> {
  final PairingStorage _storage;
  final Preferences _prefs;
  final ConnectionManager _conn;
  final RoomActivityStore _activity;
  StreamSubscription<Map<String, PresenceState>>? _presenceSub;
  StreamSubscription<Map<String, List<RoomInfo>>>? _roomsSub;
  StreamSubscription<ConnectionStatus>? _statusSub;
  bool _relayConnected = false;
  bool _disposed = false;

  /// Whether the "Offline (n)" accordion on Home is unfolded.
  bool get offlineExpanded {
    final s = state;
    return s is HomeList ? s.offlineExpanded : false;
  }

  /// Previous meta.working per `stdEpk|roomId` — lets us detect the
  /// true→false transition that means "a turn finished".
  final Map<String, bool> _prevWorking = <String, bool>{};
  bool _workingSeeded = false;

  HomeViewModel(this._storage, this._prefs, this._conn, this._activity)
    : super(const HomeLoading()) {
    _relayConnected = _conn.status is StatusOnline;
    _load();
    _presenceSub = _conn.presenceStream.listen(_onPresence);
    _roomsSub = _conn.roomsStream.listen(_onRooms);
    _statusSub = _conn.statusStream.listen(_onStatus);
    // Settings (rename / revoke) and pairing flow both write through
    // PairingStorage; listening here keeps Home in sync without manual
    // notifications between screens.
    _storage.addListener(_onStorageChanged);
    _activity.addListener(_onActivityChanged);
  }

  void _onStorageChanged() {
    if (_disposed) return;
    _load();
  }

  void _onActivityChanged() {
    if (_disposed) return;
    // Unread counts / recency changed → re-render tiles.
    _reemit();
  }

  /// `true` when the app's WS to the relay is alive (StatusOnline).
  /// When `false`, every room dot should render in the "reconnecting"
  /// colour (amber) regardless of `isRoomLive`, because the app has
  /// no fresh signal on any room.
  bool get isRelayConnected => _relayConnected;

  /// `true` when `(epk, roomId)`'s agent is currently mid-turn. Drives
  /// the blue "working" dot on the Home tile.
  ///
  /// Plan/32 — single source of truth: the relay broadcasts `meta.working`
  /// (turn_start/turn_end from the Pi-extension) to ALL subscribed rooms,
  /// exactly like presence, so this reflects EVERY session — connected or
  /// not. We deliberately do NOT OR the DB session index here: that row is
  /// only kept fresh for the currently-connected room (the SyncService
  /// writer follows the active connection), so a session that finishes
  /// while the app is on a DIFFERENT chat would never get its index idled
  /// and the dot would stay blue forever. The relay flag has no such blind
  /// spot.
  bool isRoomWorking(String epk, String roomId) =>
      _conn.isRoomWorking(epk, roomId);

  Future<void> _load() async {
    final peers = await _storage.listPeers();
    if (_disposed) return;
    if (peers.isEmpty) {
      emit(const HomeNoPeer());
      return;
    }
    // Make sure the relay is pushing updates for everyone we know about;
    // the call is idempotent so this is safe even mid-session. The same
    // subscribe also covers rooms (plan 17 — replay block in
    // ConnectionManager sends both presence and rooms subscribes).
    _conn.subscribeToPeers(peers.map((p) => p.remoteEpk).toList());
    emit(
      HomeList(
        peers: peers,
        statusByEpk: _conn.presenceSnapshot,
        roomsByPeer: _conn.roomsSnapshot,
      ),
    );
  }

  void _onPresence(Map<String, PresenceState> snapshot) {
    final s = state;
    if (s is! HomeList) return;
    emit(s.copyWith(statusByEpk: snapshot));
  }

  void _onRooms(Map<String, List<RoomInfo>> snapshot) {
    _detectUnread(snapshot);
    final s = state;
    if (s is! HomeList) return;
    emit(s.copyWith(roomsByPeer: snapshot));
  }

  /// Compares each room's meta.working against the previous snapshot.
  /// A true→false transition for a room OTHER than the one currently
  /// open in chat means a turn finished unseen → bump its unread badge.
  /// The first snapshot only seeds the map (no bumps on boot).
  void _detectUnread(Map<String, List<RoomInfo>> snapshot) {
    final selEpk = _prefs.selectedPeerEpk;
    final selRoom = _prefs.selectedRoomId ?? 'main';
    snapshot.forEach((stdEpk, rooms) {
      for (final r in rooms) {
        final key = '$stdEpk|${r.roomId}';
        final prev = _prevWorking[key];
        _prevWorking[key] = r.working;
        if (!_workingSeeded || prev != true || r.working) continue;
        final isOpen =
            selEpk != null &&
            toStandardB64(selEpk) == stdEpk &&
            selRoom == r.roomId;
        if (!isOpen) {
          // ignore: discarded_futures
          _activity.bumpUnread(stdEpk, r.roomId);
        }
      }
    });
    _workingSeeded = true;
  }

  void _onStatus(ConnectionStatus status) {
    final next = status is StatusOnline;
    if (next == _relayConnected) return;
    _relayConnected = next;
    // Trigger a re-render of any HomeList so tiles re-evaluate dot
    // colour (room-live vs reconnecting).
    _reemit();
  }

  /// Re-emit the current HomeList so `context.watch` rebuilds even though
  /// peers / rooms / presence didn't change.
  void _reemit() {
    final s = state;
    if (s is HomeList) {
      emit(
        HomeList(
          peers: s.peers,
          statusByEpk: s.statusByEpk,
          roomsByPeer: s.roomsByPeer,
          offlineExpanded: s.offlineExpanded,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Derived lists (live / offline, last-used-first ordering)
  // ---------------------------------------------------------------------------

  List<HomeItem> _allItems() {
    final s = state;
    if (s is! HomeList) return const [];
    return s.items(normalizeEpk: normalizeEpkForLookup);
  }

  bool _online(HomeItem it) =>
      _relayConnected && _conn.isRoomLive(it.peer.remoteEpk, it.room.roomId);

  /// Sessions live on the relay right now, ordered for display.
  List<HomeItem> get liveItems =>
      _ordered(_allItems().where(_online).toList());

  /// Cached sessions whose rooms are no longer announced. Rendered under
  /// the collapsed "Offline" accordion.
  List<HomeItem> get offlineItems =>
      _ordered(_allItems().where((i) => !_online(i)).toList());

  /// Display order: working first (agent mid-turn), then most recently
  /// opened, then newest session, then label — stable and predictable.
  List<HomeItem> _ordered(List<HomeItem> items) {
    int cmp(HomeItem a, HomeItem b) {
      final wa = _conn.isRoomWorking(a.peer.remoteEpk, a.room.roomId);
      final wb = _conn.isRoomWorking(b.peer.remoteEpk, b.room.roomId);
      if (wa != wb) return wa ? -1 : 1;

      final la = _activity.lastOpenedAt(
        toStandardB64(a.peer.remoteEpk),
        a.room.roomId,
      );
      final lb = _activity.lastOpenedAt(
        toStandardB64(b.peer.remoteEpk),
        b.room.roomId,
      );
      if (la != null || lb != null) {
        final ta = la?.millisecondsSinceEpoch ?? -1;
        final tb = lb?.millisecondsSinceEpoch ?? -1;
        if (ta != tb) return tb.compareTo(ta); // recent first; never-open last
      }

      if (a.room.startedAt != b.room.startedAt) {
        return b.room.startedAt.compareTo(a.room.startedAt);
      }
      return a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          );
    }

    return items..sort(cmp);
  }

  /// Unseen finished-turn count for a tile badge.
  int unreadFor(String epk, String roomId) =>
      _activity.unread(toStandardB64(epk), roomId);

  void toggleOfflineExpanded() {
    final s = state;
    if (s is! HomeList) return;
    emit(s.copyWith(offlineExpanded: !s.offlineExpanded));
  }

  /// Remember which (peer, room) the user picked. Falls back to
  /// `roomId='main'` when the caller doesn't supply one (legacy /
  /// pre-room-announce). Also flips the ConnectionManager's active
  /// room so subsequent sends carry the right outer envelope.
  ///
  /// Plan-24 follow-up: when the peer record in storage has no
  /// `roomId` yet (post-mesh-restore: the mesh blob doesn't carry
  /// per-device room data, so `PeerRecord.roomId` is null until the
  /// relay announces the room and `ConnectionManager._maybeAdoptLegacyRoom`
  /// catches up), persist the tapped roomId on the PeerRecord too.
  /// Without this, the next cold-start reads `peer.roomId=null` →
  /// `ConnectionManager._connect` falls back to room `'main'` → Pi
  /// never sees the frame → ChatViewModel sits on Connecting/offline
  /// even though the WS is alive.
  Future<void> openSession(String epk, {String? roomId}) async {
    final peers = await _storage.listPeers();
    if (_disposed) return;
    final match = peers.where((p) => p.remoteEpk == epk).cast<PeerRecord?>();
    if (match.isEmpty) return;
    final peer = match.first!;
    final effectiveRoom = (roomId == null || roomId.isEmpty) ? 'main' : roomId;
    await _prefs.setSelectedRoom(epk: epk, roomId: effectiveRoom);
    if (peer.roomId != effectiveRoom) {
      // ignore: unawaited_futures
      _storage.savePeer(peer.copyWith(roomId: effectiveRoom));
    }
    // Tell the manager which Pi-side room to address. Safe to call
    // even if the manager is mid-connect (room is applied on the next
    // send and any active StatusOnline channel).
    _conn.switchRoom(effectiveRoom);
    // Home bookkeeping: this room is now the freshest AND fully seen.
    // ignore: discarded_futures
    _activity.markOpened(toStandardB64(epk), effectiveRoom);
  }

  /// Helper for widgets: pass a peer's url-safe epk → returns standard
  /// for indexing into [HomeList.roomsByPeer] / [HomeList.statusByEpk].
  static String normalizeEpkForLookup(String epk) => toStandardB64(epk);

  /// Plan-17 follow-up — `true` if `(epk, roomId)` is currently live on
  /// the relay. Drives the presence dot on each tile (per-room, not
  /// per-peer anymore).
  bool isRoomLive(String epk, String roomId) => _conn.isRoomLive(epk, roomId);

  /// Long-press menu — rename a single room locally (Pi never sees it).
  Future<void> renameRoom(String epk, String roomId, String? name) =>
      _conn.setRoomLocalName(epk, roomId, name);

  /// Long-press menu — delete a cached room locally. Caller should
  /// gate on `!isRoomLive` (only offline rooms can be removed).
  Future<void> deleteRoom(String epk, String roomId) =>
      _conn.deleteCachedRoom(epk, roomId);

  @override
  void dispose() {
    _disposed = true;
    _presenceSub?.cancel();
    _roomsSub?.cancel();
    _statusSub?.cancel();
    _storage.removeListener(_onStorageChanged);
    _activity.removeListener(_onActivityChanged);
    super.dispose();
  }
}
