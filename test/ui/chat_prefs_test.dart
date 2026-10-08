import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/chat/message_list.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
import '../support/pump.dart';

Finder control(String label) => find.byWidgetPredicate(
  (widget) => widget is Tappable && widget.label == label,
);

FakePrefsStore withSwitch(ChatSwitch which, bool on) =>
    FakePrefsStore(const Prefs().withSwitch(which, on));

double listOffset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(MessageList),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position
    .pixels;

void main() {
  testWidgets('the Chat page shows only the switches the device can use', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer());
    h.shell.openSettings(SettingsPage.chat);
    await tester.pumpAndSettle();
    expect(control('Follow a streaming answer'), findsOneWidget);
    expect(control('Show reasoning open'), findsOneWidget);
    expect(control('Send dictation when I stop talking'), findsNothing);
    expect(control('Read answers aloud'), findsNothing);
    expect(control('Spellcheck the message'), findsNothing);
    await tester.tap(control('Show reasoning open'));
    await tester.pump();
    expect(h.prefs.prefs.isOn(ChatSwitch.reasoningOpen), isTrue);
    expect(h.prefsStore.saved.isOn(ChatSwitch.reasoningOpen), isTrue);
  });

  testWidgets('with send dictation on, a pause sends the message', (
    tester,
  ) async {
    final llm = planningServer();
    final h = await pumpApp(
      tester,
      llm: llm,
      canDictate: true,
      prefsStore: withSwitch(ChatSwitch.sendDictation, true),
    );
    await tester.tap(control('Dictate'));
    await tester.pump();
    h.dictation!.say('How long is the lease?');
    h.dictation!.finish();
    await tester.pumpAndSettle();
    expect(llm.calls, contains(startsWith('streamChat:')));
    expect(composerText(tester), isEmpty);
  });

  testWidgets('stopping dictation by hand leaves the message to send', (
    tester,
  ) async {
    final llm = planningServer();
    final h = await pumpApp(
      tester,
      llm: llm,
      canDictate: true,
      prefsStore: withSwitch(ChatSwitch.sendDictation, true),
    );
    await tester.tap(control('Dictate'));
    await tester.pump();
    h.dictation!.say('Remind me');
    await tester.tap(control('Stop dictating'));
    await tester.pumpAndSettle();
    expect(llm.calls, isNot(contains(startsWith('streamChat:'))));
    expect(composerText(tester), 'Remind me');
  });

  testWidgets('with read answers on, a finished answer is read', (
    tester,
  ) async {
    final llm = planningServer()..answer = 'Twelve months.';
    final h = await pumpApp(
      tester,
      llm: llm,
      canSpeak: true,
      prefsStore: withSwitch(ChatSwitch.readAnswers, true),
    );
    expect(h.speaker!.spoken, isEmpty);
    await h.chat.send('How long?');
    await tester.pumpAndSettle();
    expect(h.speaker!.spoken, ['Twelve months.']);
  });

  testWidgets('a model\'s failure or reasoning alone is not read aloud', (
    tester,
  ) async {
    final llm = planningServer()
      ..answer = 'The agent model failed to respond: timeout.';
    final h = await pumpApp(
      tester,
      llm: llm,
      canSpeak: true,
      prefsStore: withSwitch(ChatSwitch.readAnswers, true),
    );
    await h.chat.send('How long?');
    await tester.pumpAndSettle();
    llm.answer = '<think>Nothing to say.</think>';
    await h.chat.send('And now?');
    await tester.pumpAndSettle();
    expect(h.speaker!.spoken, isEmpty);
  });

  testWidgets('a stopped answer is not read aloud', (tester) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(
      tester,
      llm: llm,
      canSpeak: true,
      prefsStore: withSwitch(ChatSwitch.readAnswers, true),
    );
    await h.chat.send('How long?');
    llm.chat!.add(const TextChunk('Twelve'));
    await tester.pump(const Duration(milliseconds: 100));
    h.chat.stop();
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.speaker!.spoken, isEmpty);
  });

  testWidgets('with reasoning open, it shows unfolded', (tester) async {
    final llm = planningServer();
    llm.histories['budget'] = [
      const ChatMessage(role: Role.user, text: 'Colour?'),
      const ChatMessage(
        role: Role.assistant,
        text: '<think>It is a red square.</think>**red**',
      ),
    ];
    await pumpApp(
      tester,
      llm: llm,
      prefsStore: withSwitch(ChatSwitch.reasoningOpen, true),
    );
    expect(find.text('It is a red square.'), findsOneWidget);
    expect(find.text('Hide reasoning'), findsOneWidget);
  });

  for (final follow in [true, false]) {
    testWidgets('following a streaming answer ${follow ? 'on' : 'off'}', (
      tester,
    ) async {
      final llm = planningServer()..hold = true;
      final h = await pumpApp(
        tester,
        llm: llm,
        size: const Size(1280, 500),
        prefsStore: withSwitch(ChatSwitch.followAnswer, follow),
      );
      await h.chat.send('Tell me everything.');
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 12; i++) {
        llm.chat!.add(TextChunk('Paragraph $i.\n\n'));
        await tester.pump(const Duration(milliseconds: 50));
      }
      if (follow) {
        expect(listOffset(tester), 0);
      } else {
        expect(listOffset(tester), greaterThan(100));
      }
      await llm.chat!.close();
      await tester.pump(const Duration(milliseconds: 100));
    });
  }

  testWidgets('spellcheck follows its switch where the device has one', (
    tester,
  ) async {
    tester.platformDispatcher.nativeSpellCheckServiceDefinedTestValue = true;
    addTearDown(tester.platformDispatcher.clearNativeSpellCheckServiceDefined);
    final h = await pumpApp(tester, llm: planningServer(), canSpellcheck: true);
    bool spellchecks() => tester
        .widget<TextField>(
          find.ancestor(of: composerField, matching: find.byType(TextField)),
        )
        .spellCheckConfiguration!
        .spellCheckEnabled;
    expect(spellchecks(), isTrue);
    await h.prefs.setSwitch(ChatSwitch.spellcheck, false);
    await tester.pump();
    expect(spellchecks(), isFalse);
  });
}
