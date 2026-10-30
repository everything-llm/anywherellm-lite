import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/chat/answer_body.dart';
import 'package:anywherellm/ui/chat/message_list.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
import '../support/pump.dart';

/// How far the chat is scrolled up from its newest turn.
double _scrolledUp(WidgetTester tester) => tester
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

/// An answer long enough to scroll.
final _long = [for (var i = 1; i <= 80; i++) 'Line $i.'].join('\n\n');

/// Scrolls the chat up, away from its newest turn.
Future<void> _scrollUp(WidgetTester tester) async {
  await tester.drag(find.byType(MessageList), const Offset(0, 400));
  await tester.pumpAndSettle();
  expect(_scrolledUp(tester), greaterThan(0));
}

void main() {
  testWidgets('a failed answer says the answer stopped', (tester) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('And next quarter?');
    await tester.pump();
    llm.chat!.addError(const ApiException('The server stopped the answer.'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Answer stopped. The server stopped the answer.'),
      findsOneWidget,
    );
  });

  testWidgets('a busy model says so in few words, with Ask again', (
    tester,
  ) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('And next quarter?');
    await tester.pump();
    const raw =
        '429 Rate limit reached for gpt-4o on tokens per min (TPM): Limit 30000. Please '
        'try again in 20s. Visit https://platform.openai.com/account/rate-limits.';
    llm.chat!
      ..add(const TextChunk('Next quarter'))
      ..addError(const ApiException(raw));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text(
        'Answer stopped. The model is busy right now. Ask again in about 20 seconds.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('platform.openai.com'), findsNothing);
    expect(control('Ask again'), findsOneWidget);
    // Its words can be copied; there is no More.
    expect(control('Copy answer'), findsOneWidget);
    expect(control('More: read aloud, ask again, details'), findsNothing);
  });

  testWidgets('a picture refused while streaming asks without it', (
    tester,
  ) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('What does this light mean?');
    await tester.pump();
    llm.chat!.addError(
      const ApiException(
        '400 image_url is only supported by certain models.',
        status: 400,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Picture refused.'), findsOneWidget);
    await tester.tap(control('Remove the picture'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(composerText(tester), 'What does this light mean?');
  });

  testWidgets('messages waiting in a chat with no turns still show', (
    tester,
  ) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('And next quarter?');
    await tester.pump();
    expect(h.chat.sendWhenDone('And the year after?'), isTrue);
    h.chat.stop();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Paused · 1 waiting'), findsOneWidget);

    // Cleared with the message held: no turns, and the message still in view.
    await h.chat.reset();
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.chat.turns, isEmpty);
    expect(find.text('Paused · 1 waiting'), findsOneWidget);
    expect(find.text('And the year after?'), findsOneWidget);
    expect(find.text('Ask about', findRichText: true), findsNothing);

    // And in reach: Resume sends it.
    llm.hold = false;
    await tester.tap(control('Resume'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      llm.calls.where((c) => c.endsWith(':And the year after?')),
      hasLength(1),
    );
    expect(find.text('Paused · 1 waiting'), findsNothing);
  });

  testWidgets('a question the server never took says Not sent', (tester) async {
    final llm = planningServer()
      ..errors['streamChat'] = const NotSent('Could not reach the server.');
    final h = await pumpApp(tester, llm: llm);
    await typeAndEnter(tester, 'How much is recruiting?');
    await tester.pumpAndSettle();
    expect(find.text('How much is recruiting?'), findsOneWidget);
    expect(find.text('Not sent'), findsOneWidget);
    expect(control('Try again'), findsOneWidget);
    expect(control('Edit'), findsOneWidget);
    // The question is all there is: no answer box under it.
    expect(find.text('The answer stopped'), findsNothing);
    expect(h.chat.turns.last.notSent, isTrue);
  });

  testWidgets('Try again sends a question that was not sent', (tester) async {
    final llm = planningServer()
      ..errors['streamChat'] = const NotSent('Could not reach the server.');
    await pumpApp(tester, llm: llm);
    await typeAndEnter(tester, 'How much is recruiting?');
    await tester.pumpAndSettle();
    llm.errors.remove('streamChat');
    await tester.tap(control('Try again'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Not sent'), findsNothing);
    expect(find.text('How much is recruiting?'), findsOneWidget);
    expect(find.text('Here is what your sources say.'), findsOneWidget);
  });

  testWidgets('Edit puts a question that was not sent back in the box', (
    tester,
  ) async {
    final llm = planningServer()
      ..errors['streamChat'] = const NotSent('Could not reach the server.');
    await pumpApp(tester, llm: llm);
    await typeAndEnter(tester, 'How much is recruiting?');
    await tester.pumpAndSettle();
    await tester.tap(control('Edit'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(composerText(tester), 'How much is recruiting?');
    expect(find.text('Not sent'), findsNothing);
    expect(find.text('How much is recruiting?'), findsOneWidget);
  });

  testWidgets('a failed last answer can be asked again', (tester) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('And next quarter?');
    await tester.pump();
    llm.chat!.addError(const ApiException('The server stopped the answer.'));
    await tester.pump(const Duration(milliseconds: 300));
    llm.hold = false;
    final before = llm.calls.where((c) => c.startsWith('streamChat')).length;
    await tester.tap(find.text('Ask again'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      llm.calls.where((c) => c.startsWith('streamChat')).length,
      before + 1,
    );
    expect(llm.calls.last, contains('And next quarter?'));
  });

  testWidgets('a failed answer that is not the last has no Ask again', (
    tester,
  ) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('And next quarter?');
    await tester.pump();
    llm.chat!.addError(const ApiException('The server stopped the answer.'));
    await tester.pump(const Duration(milliseconds: 300));
    llm.hold = false;
    await h.chat.send('Never mind.');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ask again'), findsNothing);
  });

  testWidgets('a stopped answer says the server may still save it', (
    tester,
  ) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('And next quarter?');
    await tester.pump();
    llm.chat!.add(const TextChunk('Next quarter we'));
    await tester.pump();
    expect(find.text('Stopped · the server may still save it'), findsNothing);
    h.chat.stop();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Stopped · the server may still save it'), findsOneWidget);
  });

  testWidgets('a one-line answer starts where a wrapped one does', (
    tester,
  ) async {
    final llm = planningServer();
    llm.histories['budget'] = [
      const ChatMessage(role: Role.user, text: 'Tell me everything.'),
      ChatMessage(role: Role.assistant, text: 'All of it. ' * 80),
      const ChatMessage(role: Role.user, text: 'Is that all?'),
      const ChatMessage(role: Role.assistant, text: 'Yes.'),
      const ChatMessage(role: Role.user, text: 'Thanks.'),
      const ChatMessage(role: Role.assistant, text: 'Any time.'),
    ];
    await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    expect(find.byType(AnswerBody), findsNWidgets(3));
    double start(String text) => tester
        .getTopLeft(
          find.ancestor(
            of: find.textContaining(text, findRichText: true).first,
            matching: find.byType(AnswerBody),
          ),
        )
        .dx;
    final wrapped = start('All of it.');
    expect(start('Yes.'), wrapped);
    // The latest answer sits on a tile 8 out past the column, its text inside the tile's edge
    // and 16 of padding.
    expect(start('Any time.'), wrapped - 8 + 1 + 16);
  });

  testWidgets('sending while scrolled up brings the new question into view', (
    tester,
  ) async {
    final llm = answering(_long)..hold = true;
    await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    await _scrollUp(tester);

    await tester.enterText(composerField, 'And then?');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(_scrolledUp(tester), 0);
    expect(find.text('And then?'), findsOneWidget);
  });

  testWidgets('scrolled up, a button jumps back to the newest message', (
    tester,
  ) async {
    final llm = answering(_long);
    await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    final jump = control('Jump to the newest message');
    expect(jump, findsNothing, reason: 'at the newest text it does not show');

    await _scrollUp(tester);
    expect(jump, findsOneWidget);
    await tester.tap(jump);
    await tester.pumpAndSettle();
    expect(_scrolledUp(tester), 0);
    expect(jump, findsNothing);
  });

  testWidgets('a streaming answer that runs past view shows the button', (
    tester,
  ) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(
      tester,
      llm: llm,
      size: const Size(390, 500),
      prefsStore: FakePrefsStore(
        const Prefs().withSwitch(ChatSwitch.followAnswer, false),
      ),
    );
    await h.chat.send('Tell me everything.');
    await tester.pump(const Duration(milliseconds: 300));
    final jump = control('Jump to the newest message');
    expect(jump, findsNothing);
    for (var i = 0; i < 12; i++) {
      llm.chat!.add(TextChunk('Paragraph $i.\n\n'));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(jump, findsOneWidget);
    await llm.chat!.close();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('another chat opens at its newest turn', (tester) async {
    final llm = answering(_long);
    final h = await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    await _scrollUp(tester);
    llm.histories['priorities'] = [...llm.histories['budget']!];
    await h.chat.open('priorities');
    await tester.pumpAndSettle();
    expect(_scrolledUp(tester), 0);
  });

  testWidgets('a long answer pins its question, and a tap scrolls back to it', (
    tester,
  ) async {
    await pumpApp(tester, llm: answering(_long));
    await tester.pumpAndSettle();
    // The chat opens at the end of the answer, its question scrolled up out of view.
    final pinned = control('Back to the question: Where?');
    expect(pinned, findsOneWidget);

    await tester.tap(pinned);
    await tester.pumpAndSettle();
    expect(pinned, findsNothing);
    final list = tester.getRect(find.byType(MessageList));
    final question = tester.getRect(find.text('Where?'));
    expect(question.top, greaterThanOrEqualTo(list.top));
    expect(question.bottom, lessThanOrEqualTo(list.bottom));
  });

  testWidgets('a question in view is not pinned', (tester) async {
    await pumpApp(tester, llm: answering('Here.'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is Tappable && w.label.startsWith('Back to the question'),
      ),
      findsNothing,
    );
  });
}
