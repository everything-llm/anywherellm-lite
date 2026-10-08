import 'dart:async';

import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/ui/chat/answer_body.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// Whether the answer that shows [text] is drawn in the second ink.
bool muted(WidgetTester tester, String text) => tester
    .widget<AnswerBody>(
      find.byWidgetPredicate((w) => w is AnswerBody && w.text == text),
    )
    .muted;

void main() {
  testWidgets('Stop is named for what it stops', (tester) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('And next quarter?');
    await tester.pump();
    expect(find.byTooltip('Stop the answer'), findsOneWidget);
  });

  testWidgets('a stopped answer keeps Retry and its text in the second ink', (
    tester,
  ) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('And next quarter?');
    await tester.pump();
    llm.chat!.add(const TextChunk('Next quarter we'));
    await tester.pump();
    expect(muted(tester, 'Next quarter we'), isFalse);
    h.chat.stop();
    await tester.pump(const Duration(milliseconds: 300));
    expect(muted(tester, 'Next quarter we'), isTrue);
    expect(find.byTooltip('Retry'), findsOneWidget);
  });

  testWidgets('a failed answer asks again in its box, not twice', (
    tester,
  ) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('And next quarter?');
    await tester.pump();
    llm.chat!
      ..add(const TextChunk('Next quarter we'))
      ..addError(const ApiException('The server stopped the answer.'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ask again'), findsOneWidget);
    expect(find.byTooltip('Retry'), findsNothing);
    // The chat's earlier answer has its own Copy.
    expect(find.byTooltip('Copy answer'), findsNWidgets(2));
    expect(muted(tester, 'Next quarter we'), isTrue);
  });

  testWidgets('an answer still being written says so as drawn', (tester) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('And next quarter?');
    await tester.pump();
    llm.chat!.addError(const AnswerStillRunning());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('when it’s done'), findsOneWidget);
  });

  testWidgets(
    'a message the chat is already answering waits in the composer for that answer',
    (tester) async {
      const message = 'And a shorter one for the team call?';
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm);
      final events = StreamController<ChatEvent>();
      addTearDown(() => unawaited(events.close()));
      llm
        ..running['budget'] = (question: 'Asked on the phone', events: events)
        ..errors['streamChat'] = const AlreadyAnswering(
          'That thread already has an answer running.',
        );
      await tester.enterText(composerField, message);
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'This chat is still answering, maybe on another device. Send when it ends, or '
          'stop it.',
        ),
        findsOneWidget,
      );
      expect(find.text('The answer stopped'), findsNothing);
      expect(
        tester.widget<EditableText>(composerField).controller.text,
        message,
      );
      expect(find.text('Asked on the phone'), findsOneWidget);
      expect(find.byTooltip('Stop the answer'), findsOneWidget);
      expect(h.chat.busy, isTrue);
      await tester.tap(find.byTooltip('Send when done'));
      await tester.pump();
      expect(find.text('Sends when this answer ends.'), findsOneWidget);
      llm.errors.remove('streamChat');
      events.add(const TextChunk('Short.'));
      await events.close();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        llm.calls.where((c) => c == 'streamChat:budget:$message'),
        hasLength(2),
      );
      expect(find.textContaining('maybe on another device'), findsNothing);
      expect(
        tester.widget<EditableText>(composerField).controller.text,
        isEmpty,
      );
    },
  );
}
