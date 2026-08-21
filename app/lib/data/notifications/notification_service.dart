import 'dart:async';
import 'dart:io' show Platform;

import 'package:app/data/notifications/notification_gate.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/domain/contracts/service.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Android local notifications for Pi activity while the app is backgrounded.
///
/// These are **not** FCM pushes. They only fire while this isolate is still
/// alive (recent app switch). After Android kills the process, nothing is
/// delivered until the user opens the app again — reconnect-on-resume covers
/// that path.
class NotificationService extends Service {
  NotificationService({
    required Preferences prefs,
    required SyncService sync,
    FlutterLocalNotificationsPlugin? plugin,
    NotificationGate? gate,
  }) : _prefs = prefs,
       _sync = sync,
       _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _gate = gate ?? NotificationGate();

  static const _channelId = 'remote_pi_events';
  static const _channelName = 'Pi activity';
  static const _turnId = 1;
  static const _inputId = 2;

  final Preferences _prefs;
  final SyncService _sync;
  final FlutterLocalNotificationsPlugin _plugin;
  final NotificationGate _gate;

  StreamSubscription<bool>? _workingSub;
  StreamSubscription<ExtensionUiRequest>? _uiSub;
  bool _inited = false;

  NotificationGate get gate => _gate;

  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    _gate.enabled = _prefs.notificationsEnabled;
    _prefs.addListener(_onPrefs);
    // Seed so a turn already in flight still notifies when it ends.
    _gate.onWorkingChanged(_sync.isWorking);

    try {
      if (Platform.isAndroid) {
        const android = AndroidInitializationSettings('@drawable/ic_stat_remotepi');
        await _plugin.initialize(
          const InitializationSettings(android: android),
        );
        final androidPlugin = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await androidPlugin?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'When Pi finishes working or needs your input',
            importance: Importance.high,
          ),
        );
      }
    } catch (_) {
      // Plugin failure must not block app start.
    }

    _workingSub = _sync.workingStream.listen((w) {
      final payload = _gate.onWorkingChanged(w);
      if (payload != null) {
        // ignore: unawaited_futures
        _show(_turnId, payload.title, payload.body);
      }
    });
    _uiSub = _sync.extensionUiRequestStream.listen((req) {
      final payload = _gate.onNeedsInput(req.method);
      if (payload != null) {
        // ignore: unawaited_futures
        _show(_inputId, payload.title, payload.body);
      }
    });
  }

  void setBackgrounded(bool value) {
    _gate.backgrounded = value;
    if (value) {
      if (_gate.enabled) {
        // Ask only when we actually need it (first background), not on
        // every cold start before pairing.
        // ignore: unawaited_futures
        requestPermission();
      }
    } else if (Platform.isAndroid) {
      // ignore: unawaited_futures
      _cancelQuietly();
    }
  }

  Future<void> requestPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  void _onPrefs() {
    final on = _prefs.notificationsEnabled;
    final was = _gate.enabled;
    _gate.enabled = on;
    if (on && !was) {
      // ignore: unawaited_futures
      requestPermission();
    }
    if (!on && Platform.isAndroid) {
      // ignore: unawaited_futures
      _cancelQuietly();
    }
  }

  Future<void> _show(int id, String title, String body) async {
    if (!Platform.isAndroid) return;
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'When Pi finishes working or needs your input',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@drawable/ic_stat_remotepi',
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _cancelQuietly() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefs);
    _workingSub?.cancel();
    _uiSub?.cancel();
    super.dispose();
  }
}
