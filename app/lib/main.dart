import 'dart:async';
import 'dart:io';

import 'package:app/config/dependencies.dart';
import 'package:app/data/local/boxes.dart';
import 'package:app/data/mesh/mesh_sync_service.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/notifications/notification_service.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void _log(String line) {
  try {
    final f = File(r'C:\Users\Purple\AppData\Local\Temp\remote_pi_dart.log');
    f.writeAsStringSync('[$DateTime.now()] $line\n', mode: FileMode.append);
  } catch (_) {}
}

void main() async {
  _log('Dart main() started');
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    _log('WidgetsFlutterBinding initialized');
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _log('[FlutterError] ${details.exception}\n${details.stack}');
    };
    try {
      _log('Initializing LocalBoxes');
      await LocalBoxes.init();
      _log('LocalBoxes initialized, running setupDependencies');
      await setupDependencies();
      _log('setupDependencies done, getting SyncService');
      injector.get<SyncService>();
      _log('Calling runApp(RemotePiApp)');
      runApp(const RemotePiApp());
      _log('runApp returned');
    } catch (e, st) {
      _log('[StartupError] $e\n$st');
      runApp(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text('Fatal Startup Error:\n$e\n\n$st'),
            ),
          ),
        ),
      ));
    }
  }, (error, stack) {
    _log('[ZoneError] $error\n$stack');
  });
}

class RemotePiApp extends StatefulWidget {
  const RemotePiApp({super.key});

  @override
  State<RemotePiApp> createState() => _RemotePiAppState();
}

class _RemotePiAppState extends State<RemotePiApp> with WidgetsBindingObserver {
  late final _router = buildRouter(
    injector.get<PairingStorage>(),
    injector.get<ConnectionManager>(),
    injector.get<Preferences>(),
    injector.get<OwnerIdentityBridge>(),
    injector.get<MeshSyncService>(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disposeDependencies();
    super.dispose();
  }

  /// Mesh poll + WS reconnect + notification gate follow the app
  /// lifecycle. Polling and a stale-socket reconnect run on resume;
  /// paused/hidden/detached stop polling and mark the app backgrounded.
  /// `inactive` is ignored (permission dialogs, iOS app switcher).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final meshSync = injector.get<MeshSyncService>();
    final conn = injector.get<ConnectionManager>();
    final notif = injector.get<NotificationService>();
    switch (state) {
      case AppLifecycleState.resumed:
        meshSync.startPolling();
        // ignore: unawaited_futures
        meshSync.pullOnDemand();
        notif.setBackgrounded(false);
        // ignore: unawaited_futures
        conn.onForeground();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        meshSync.stopPolling();
        conn.onBackground();
        notif.setBackgrounded(true);
      case AppLifecycleState.inactive:
        // iOS app-switcher / Android transient — don't treat as background.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Preferences>.value(
          value: injector.get<Preferences>(),
        ),
        ChangeNotifierProvider<SessionSelection>.value(
          value: injector.get<SessionSelection>(),
        ),
        // Shell layout state — lets the adaptive shell collapse the split
        // into a single centered pane on zero-state Home (no Pi / empty).
        ChangeNotifierProvider<ShellLayout>.value(
          value: injector.get<ShellLayout>(),
        ),
      ],
      // Theme is reactive: toggling the mode in Settings notifies
      // [Preferences] → this Consumer rebuilds → MaterialApp swaps theme.
      child: Consumer<Preferences>(
        builder: (context, prefs, _) => MaterialApp.router(
          title: 'Remote Pi',
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: prefs.themeMode,
          routerConfig: _router,
          debugShowCheckedModeBanner: false,
          // Issue #114 — user-chosen text size. Applied here rather than by
          // scaling `AppTypography`'s base sizes so the many per-widget
          // `copyWith(fontSize: …)` overrides scale too. `TextScaler.linear`
          // REPLACES the platform scaler, which is deliberate: Flutter can't
          // read iOS's per-app Text Size anyway (it only reads the global
          // accessibility setting), so honoring both would compound them.
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: prefs.fontScale.factor,
            maxScaleFactor: prefs.fontScale.factor,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
