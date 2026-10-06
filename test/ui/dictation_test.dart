import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

Finder control(String label) => find.byWidgetPredicate(
  (widget) => widget is Tappable && widget.label == label,
);

String message(WidgetTester tester) =>
    tester.widget<EditableText>(composerField).controller.text;

void main() {
  testWidgets('there is no microphone where the device cannot listen', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer());
    expect(control('Dictate'), findsNothing);
  });

  testWidgets('what is said fills the message, and Stop keeps it', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer(), canDictate: true);
    await tester.enterText(composerField, 'Remind me');
    await tester.tap(control('Dictate'));
    await tester.pump();
    expect(h.dictation!.listening, isTrue);
    h.dictation!.say('to');
    h.dictation!.say('to call Ana');
    await tester.pump();
    expect(message(tester), 'Remind me to call Ana');
    expect(control('Stop dictating'), findsOneWidget);
    await tester.tap(control('Stop dictating'));
    await tester.pump();
    expect(h.dictation!.stopped, 1);
    expect(control('Dictate'), findsOneWidget);
    expect(message(tester), 'Remind me to call Ana');
  });

  testWidgets('a pause ends the go by itself', (tester) async {
    final h = await pumpApp(tester, llm: planningServer(), canDictate: true);
    await tester.tap(control('Dictate'));
    await tester.pump();
    h.dictation!.say('hello');
    h.dictation!.finish();
    await tester.pump();
    expect(control('Dictate'), findsOneWidget);
    expect(message(tester), 'hello');
  });

  testWidgets('a device that cannot listen says so', (tester) async {
    final h = await pumpApp(tester, llm: planningServer(), canDictate: true);
    h.dictation!.available = false;
    await tester.tap(control('Dictate'));
    await tester.pump();
    expect(find.text('Could not listen'), findsOneWidget);
    expect(control('Dictate'), findsOneWidget);
  });

  testWidgets('sending ends the go and drops what comes after', (tester) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm, canDictate: true);
    await tester.tap(control('Dictate'));
    await tester.pump();
    h.dictation!.say('what is the budget');
    await tester.pump();
    await tester.tap(control('Send'));
    await tester.pump();
    expect(h.dictation!.stopped, 1);
    expect(message(tester), isEmpty);
    await tester.pumpAndSettle();
    expect(control('Dictate'), findsOneWidget);
  });
}
