// A document's text that arrives after the text page is drawn.
import 'dart:async';

import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump.dart';
import '../../tool/sample.dart';

void main() {
  testWidgets('the text page shows text that arrives late', (tester) async {
    final llm = sampleServer();
    final gate = Completer<void>();
    llm.gates['document'] = gate;
    final h = await pumpApp(
      tester,
      llm: llm,
      size: phoneSize,
      shelf: true,
      connection: sampleServerConnection,
    );
    await tester.pumpAndSettle();
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    h.shell.openSources();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home insurance.pdf'));
    await tester.pumpAndSettle();
    expect(
      find.text('Loading…'),
      findsOneWidget,
      reason: 'while the server reads',
    );
    gate.complete();
    await tester.pumpAndSettle();
    expect(
      find.text('Loading…'),
      findsNothing,
      reason: 'once the server answered',
    );
    expect(find.text('The text of Home insurance.pdf.'), findsOneWidget);
  });
}
