import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Per-room local activity: when the user last opened a chat and how
/// many finished turns went unseen. Backs the Home tile unread badge
/// and the last-used-first ordering.
///
/// Durable (survives restarts) via the `rp_v2/room_activity` Hive box.
/// When constructed without a box (unit tests) it degrades to an
/// in-memory map.
class RoomActivityStore extends ChangeNotifier {
  RoomActivityStore({Box<dynamic>? box}) : _box = box;

  final Box<dynamic>? _box;
  final Map<String, Map<String, dynamic>> _mem = <String, Map<String, dynamic>>{};

  static String keyOf(String epk, String roomId) => '$epk:$roomId';

  Map<String, dynamic> _entry(String key) {
    final b = _box;
    if (b == null) return _mem[key] ?? <String, dynamic>{};
    final raw = b.get(key);
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  void _write(String key, Map<String, dynamic> entry) {
    final b = _box;
    if (b == null) {
      _mem[key] = entry;
    } else {
      b.put(key, entry);
    }
    notifyListeners();
  }

  /// When the user last opened this room's chat. Null = never opened.
  DateTime? lastOpenedAt(String epk, String roomId) {
    final lo = _entry(keyOf(epk, roomId))['lo'];
    return lo is int ? DateTime.fromMillisecondsSinceEpoch(lo) : null;
  }

  /// Finished turns that landed while another chat was open.
  int unread(String epk, String roomId) {
    final u = _entry(keyOf(epk, roomId))['u'];
    return u is int ? u : 0;
  }

  /// Record an open of the room's chat: stamps recency and clears the
  /// unread counter. [at] overrides the timestamp (tests).
  Future<void> markOpened(String epk, String roomId, {DateTime? at}) async {
    final ts = (at ?? DateTime.now()).millisecondsSinceEpoch;
    _write(keyOf(epk, roomId), {'lo': ts, 'u': 0});
  }

  /// One more unseen finished turn for this room.
  Future<void> bumpUnread(String epk, String roomId) async {
    final key = keyOf(epk, roomId);
    final e = _entry(key);
    _write(key, {'lo': e['lo'], 'u': ((e['u'] as int?) ?? 0) + 1});
  }
}
