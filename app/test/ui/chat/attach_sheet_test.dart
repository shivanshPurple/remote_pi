// Plan/30 + tablet fix — the Camera/Gallery attach sheet must close when the
// tablet's selected session changes out from under it.

import 'package:app/config/platform.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/chat/widgets/attach_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('attach sheet closes when the session changes', (tester) async {
    final selection = SessionSelection()..select('e1', 'r1', 'Chat 1');
    addTearDown(selection.dispose);

    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<SessionSelection>.value(
          value: selection,
          child: Builder(
            builder: (context) {
              pageContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      ),
    );

    // ignore: unawaited_futures
    showAttachSheet(pageContext);
    await tester.pumpAndSettle();
    // Camera is mobile-only; desktop offers the file picker only.
    expect(
      find.byKey(const Key('attach-camera')),
      isDesktop ? findsNothing : findsOneWidget,
    );
    expect(find.byKey(const Key('attach-gallery')), findsOneWidget);

    // Switch session on the tablet master list → sheet must dismiss.
    selection.select('e2', 'r2', 'Chat 2');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('attach-gallery')), findsNothing);
  });
}
