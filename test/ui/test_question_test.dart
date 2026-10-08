import 'package:anywherellm/ui/sources/sources_panel.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

Finder control(String label) => find.byWidgetPredicate(
  (widget) => widget is Tappable && widget.label == label,
);

Finder inSources(Finder finder) =>
    find.descendant(of: find.byType(SourcesPanel), matching: finder);

void main() {
  testWidgets('a question shows what it finds, and a hit lights its file', (
    tester,
  ) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm);
    await tapVisible(tester, control('Test a question'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Test a question'), findsOneWidget);
    await tester.enterText(inSources(find.byType(TextField)).first, 'roadmap');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(llm.calls, contains('searchDocs:q3:roadmap'));
    expect(
      find.text('What an answer would read, closest first:'),
      findsOneWidget,
    );
    expect(find.text('A passage of Q3 roadmap.pdf.'), findsOneWidget);
    expect(find.text('90% match'), findsOneWidget);
    expect(
      find.textContaining('Match is how close a passage is to the question'),
      findsOneWidget,
    );
    await tapVisible(tester, control('Q3 roadmap.pdf, 90% match'));
    await tester.pump();
    expect(h.sources.flashed, isNotNull);
    // The flash fills the file's row and rings it in the accent.
    final ring = tester
        .widgetList<AnimatedContainer>(
          find.ancestor(
            of: inSources(find.text('Q3 roadmap.pdf')),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .map((row) => (row.decoration as BoxDecoration?)?.border)
        .whereType<Border>()
        .single;
    expect(ring.top.color, isNot(Colors.transparent));
    expect(ring.top.width, 1);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tapVisible(tester, control('Done'));
    await tester.pumpAndSettle();
    expect(h.sources.hits, isNull);
    expect(control('Test a question'), findsOneWidget);
  });

  testWidgets('a question that finds nothing says so', (tester) async {
    final llm = planningServer();
    await pumpApp(tester, llm: llm);
    await tapVisible(tester, control('Test a question'));
    await tester.pumpAndSettle();
    await tester.enterText(inSources(find.byType(TextField)).first, 'zebras');
    await tester.pump();
    await tapVisible(tester, control('Test'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('searchDocs:q3:zebras'));
    expect(
      find.text('Nothing in the switched-on files comes close enough.'),
      findsOneWidget,
    );
  });
}
