import 'package:app/protocol/protocol.dart';

/// Pure decision logic for background notifications. No plugins, no IO —
/// unit-tested without Flutter bindings.
class NotificationGate {
  bool backgrounded = false;
  bool enabled = true;
  bool _working = false;

  /// Call on every [SyncService.workingStream] event.
  /// Returns a notification payload when a turn just finished in background.
  ({String title, String body})? onWorkingChanged(bool working) {
    final finished = _working && !working;
    _working = working;
    if (!enabled || !backgrounded || !finished) return null;
    return (title: 'Remote Pi', body: 'Pi finished working');
  }

  /// Call on [SyncService.extensionUiRequestStream]. `notify` is
  /// fire-and-forget (no user action) so it does not alert.
  ({String title, String body})? onNeedsInput(ExtensionUiMethod method) {
    if (!enabled || !backgrounded) return null;
    if (method == ExtensionUiMethod.notify) return null;
    return (title: 'Remote Pi', body: 'Pi needs your input');
  }
}
