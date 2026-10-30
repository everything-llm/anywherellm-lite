import 'dart:async';

import 'package:anywherellm/ui/widgets/buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

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
    // Listening reads as more than a tint: a stop mark on the accent.
    final listening = tester.widget<IconBtn>(
      find.ancestor(
        of: control('Stop dictating'),
        matching: find.byType(IconBtn),
      ),
    );
    expect(listening.icon, 'stopCircle');
    expect((listening.active, listening.solid), (true, true));
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

  testWidgets('a change to the message ends the go, and is kept', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer(), canDictate: true);
    await tester.tap(control('Dictate'));
    await tester.pump();
    h.dictation!.say('hello');
    await tester.pump();
    await tester.enterText(composerField, 'Typed instead');
    await tester.pump();
    expect(h.dictation!.stopped, 1);
    expect(control('Dictate'), findsOneWidget);
    h.dictation!.say('hello there');
    await tester.pump();
    expect(message(tester), 'Typed instead');
  });

  testWidgets('a device that cannot listen says so', (tester) async {
    final h = await pumpApp(tester, llm: planningServer(), canDictate: true);
    h.dictation!.available = false;
    await tester.tap(control('Dictate'));
    await tester.pump();
    expect(
      find.text(
        'Can’t listen. Speech input is off for this app. Turn it on in Android '
        'settings.',
      ),
      findsOneWidget,
    );
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

  testWidgets(
    'the microphone still stops a go when an answer starts meanwhile',
    (tester) async {
      final llm = planningServer()..hold = true;
      final h = await pumpApp(tester, llm: llm, canDictate: true);
      await tester.tap(control('Dictate'));
      await tester.pump();
      h.dictation!.say('and the lease');
      // A message that was waiting goes, and the chat answers while the go listens.
      unawaited(h.chat.send('Something else'));
      await tester.pump();
      expect(h.chat.busy, isTrue);
      await tester.tap(control('Stop dictating'));
      await tester.pump();
      expect(h.dictation!.stopped, 1);
      expect(control('Dictate'), findsOneWidget);
      // A go starts while the chat answers too, for the next message.
      await tester.tap(control('Dictate'));
      await tester.pump();
      expect(h.dictation!.listening, isTrue);
      await tester.tap(control('Stop dictating'));
      await tester.pump();
      await llm.chat!.close();
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
