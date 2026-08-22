// Plan/31 — local SSOT box layer (Hive v2).
//
// Three families of box in a NEW namespace (`rp_v2`); v1 (`session_history`,
// the blob snapshot) is abandoned without migration (#6 — re-sync from the Pi
// on first boot). The `runtime` box is VOLATILE: wiped on every boot (#3) so
// connection/presence never report stale online across restarts.
//
//   DURABLE  msgs_<epk>__<roomId>   key = seq (int)        → MessageRecord
//   DURABLE  sessions_index         key = <epk>:<roomId>   → SessionIndexRecord
//   VOLATILE runtime  (wiped@boot)  key = <epk>:<roomId>   → RuntimeRecord

import 'dart:io';

import 'package:app/data/transport/epk_encoding.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String _kNamespace = 'rp_v2';
const String _kSessionsIndex = 'sessions_index';
const String _kRoomActivity = 'room_activity';
const String _kRuntime = 'runtime';

/// Facade over the v2 Hive boxes. A single instance is shared by the
/// [SyncService] (writer) and the read repositories (readers) so they observe
/// the same open box objects (`Hive.openBox` is idempotent).
class LocalBoxes {
  static bool _initialized = false;
  static String? _boxPath;

  /// Resolves the base directory for Hive boxes in a resilient, cross-platform manner.
  static Future<String> resolveBoxDirectory() async {
    // 1. Check legacy directory first so existing installations keep their data
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final legacyPath = p.join(docDir.path, _kNamespace);
      final legacyDir = Directory(legacyPath);
      if (legacyDir.existsSync() && legacyDir.listSync().isNotEmpty) {
        return legacyPath;
      }
    } catch (_) {}

    // 2. Standard location for app databases on desktop / mobile
    try {
      final supportDir = await getApplicationSupportDirectory();
      return p.join(supportDir.path, _kNamespace);
    } catch (_) {}

    // 3. Fall back to Documents directory if support dir was unavailable
    try {
      final docDir = await getApplicationDocumentsDirectory();
      return p.join(docDir.path, _kNamespace);
    } catch (_) {}

    // 4. Fall back to standard OS environment paths if path_provider throws (e.g. missing xdg-user-dirs on Arch Linux)
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    if (Platform.isLinux || Platform.isMacOS) {
      final xdgData = Platform.environment['XDG_DATA_HOME'];
      if (xdgData != null && xdgData.isNotEmpty) {
        return p.join(xdgData, 'remote_pi', _kNamespace);
      }
      return p.join(home, '.local', 'share', 'remote_pi', _kNamespace);
    } else if (Platform.isWindows) {
      final localAppData =
          Platform.environment['LOCALAPPDATA'] ?? Platform.environment['APPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return p.join(localAppData, 'remote_pi', _kNamespace);
      }
      return p.join(home, 'AppData', 'Local', 'remote_pi', _kNamespace);
    }

    return p.join(home, '.remote_pi', _kNamespace);
  }

  /// Open the v2 namespace and the always-on boxes; **wipe `runtime`** before
  /// anything subscribes (#3 / Risk 2). Call once during bootstrap, before
  /// `runApp` and before any read-repo is constructed.
  static Future<void> init() async {
    if (_initialized) return;
    WidgetsFlutterBinding.ensureInitialized();
    if (!kIsWeb) {
      final targetPath = await resolveBoxDirectory();
      _boxPath = targetPath;
      final dir = Directory(targetPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      Hive.init(targetPath);
    }
    _cleanStaleLocks();
    await _openCommon();
    _initialized = true;
  }

  /// For tests: open against a custom directory. Unlike [init] this always
  /// re-opens + wipes the volatile box, so a second call simulates a restart
  /// (and lets tests assert the wipe).
  static Future<void> initForTest(String path) async {
    if (!_initialized) {
      _boxPath = path;
      Hive.init(path);
    }
    _cleanStaleLocks();
    await _openCommon();
    _initialized = true;
  }

  static void _cleanStaleLocks() {
    try {
      final p = _boxPath;
      if (p == null) return;
      final dir = Directory(p);
      if (dir.existsSync()) {
        for (final file in dir.listSync().whereType<File>()) {
          final name = file.uri.pathSegments.last;
          if (name.endsWith('.lock')) {
            final boxName = name.substring(0, name.length - 5);
            if (!Hive.isBoxOpen(boxName)) {
              try {
                file.deleteSync();
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
  }

  static Future<void> _openCommon() async {
    try {
      await Hive.openBox<dynamic>(_kSessionsIndex);
    } catch (_) {
      _cleanStaleLocks();
      await Hive.openBox<dynamic>(_kSessionsIndex);
    }
    try {
      await Hive.openBox<dynamic>(_kRoomActivity);
    } catch (_) {
      _cleanStaleLocks();
      await Hive.openBox<dynamic>(_kRoomActivity);
    }
    try {
      final runtime = await Hive.openBox<dynamic>(_kRuntime);
      await runtime.clear(); // VOLATILE — zero on boot (#3)
    } catch (_) {
      _cleanStaleLocks();
      final runtime = await Hive.openBox<dynamic>(_kRuntime);
      await runtime.clear();
    }
  }

  Box<dynamic> sessionsIndexBox() => Hive.box<dynamic>(_kSessionsIndex);

  /// Durable per-room activity (last opened, unread count) backing the
  /// Home tile badge + last-used ordering.
  Box<dynamic> roomActivityBox() => Hive.box<dynamic>(_kRoomActivity);

  Box<dynamic> runtimeBox() => Hive.box<dynamic>(_kRuntime);

  /// Per-session message box. Lazily opened; idempotent (returns the already
  /// open box on subsequent calls).
  Future<Box<dynamic>> msgsBox(String epk, String roomId) async {
    final name = msgsBoxName(epk, roomId);
    try {
      return await Hive.openBox<dynamic>(name);
    } catch (_) {
      _cleanStaleLocks();
      return await Hive.openBox<dynamic>(name);
    }
  }

  /// Synchronous accessor for a msgs box known to be open already.
  Box<dynamic> openMsgsBox(String epk, String roomId) =>
      Hive.box<dynamic>(msgsBoxName(epk, roomId));

  bool isMsgsBoxOpen(String epk, String roomId) =>
      Hive.isBoxOpen(msgsBoxName(epk, roomId));

  /// `:` and the epk's `/`+`=` would break the on-disk filename — sanitise to
  /// the url-safe, unpadded epk form (same approach as the v1 store).
  static String msgsBoxName(String epk, String roomId) =>
      'msgs_${toAppEpk(epk)}__$roomId';

  static String sessionKey(String epk, String roomId) => '$epk:$roomId';
}
