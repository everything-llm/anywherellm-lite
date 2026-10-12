import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/ui/chat/message_list.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
import '../support/pump.dart';

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
    // Reasoning opens from an answer's More menu only.
    expect(control('Show reasoning open'), findsNothing);
    expect(control('Send dictation when I stop talking'), findsNothing);
    expect(control('Read answers aloud'), findsNothing);
    expect(control('Spellcheck the message'), findsNothing);
    await tester.tap(control('Follow a streaming answer'));
    await tester.pump();
    expect(h.prefs.prefs.isOn(ChatSwitch.followAnswer), isFalse);
    expect(h.prefsStore.saved.isOn(ChatSwitch.followAnswer), isFalse);
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

  for (final follow in [true, false]) {
    testWidgets('following a streaming answer ${follow ? 'on' : 'off'}', (
      tester,
    ) async {
      final llm = planningServer()..hold = true;
      final h = await pumpApp(
        tester,
        llm: llm,
        size: const Size(390, 500),
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

  testWidgets('scrolled up, a streaming answer leaves what is in view put', (
    tester,
  ) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm, size: const Size(390, 500));
    await h.chat.send('Tell me everything.');
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 12; i++) {
      llm.chat!.add(TextChunk('Paragraph $i.\n\n'));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(listOffset(tester), 0, reason: 'at the bottom it follows');
    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(MessageList),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scroll.position.jumpTo(120);
    await tester.pump();
    final read = find.textContaining('Paragraph 9.');
    final before = tester.getTopLeft(read).dy;
    for (var i = 12; i < 20; i++) {
      llm.chat!.add(TextChunk('Paragraph $i.\n\n'));
      await tester.pump(const Duration(milliseconds: 50));
      // Held in the same frame the answer grew, so it never jumps and comes back.
      expect(tester.getTopLeft(read).dy, moreOrLessEquals(before, epsilon: 1));
    }
    expect(listOffset(tester), greaterThan(120));
    await llm.chat!.close();
    await tester.pump(const Duration(milliseconds: 100));
  });

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
