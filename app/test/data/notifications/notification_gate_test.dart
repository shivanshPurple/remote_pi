import 'package:app/data/notifications/notification_gate.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationGate', () {
    test('turn complete in background emits a notification', () {
      final g = NotificationGate()..backgrounded = true;
      expect(g.onWorkingChanged(true), isNull);
      final n = g.onWorkingChanged(false);
      expect(n, isNotNull);
      expect(n!.title, 'Remote Pi');
      expect(n.body, contains('finished'));
    });

    test('turn complete in foreground is silent', () {
      final g = NotificationGate()..backgrounded = false;
      g.onWorkingChanged(true);
      expect(g.onWorkingChanged(false), isNull);
    });

    test('disabled gate is silent even in background', () {
      final g = NotificationGate()
        ..backgrounded = true
        ..enabled = false;
      g.onWorkingChanged(true);
      expect(g.onWorkingChanged(false), isNull);
    });

    test('needs-input in background emits; notify method does not', () {
      final g = NotificationGate()..backgrounded = true;
      expect(g.onNeedsInput(ExtensionUiMethod.confirm), isNotNull);
      expect(g.onNeedsInput(ExtensionUiMethod.notify), isNull);
      g.backgrounded = false;
      expect(g.onNeedsInput(ExtensionUiMethod.input), isNull);
    });
  });
}
