import 'dart:async';

import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/chat/answer_body.dart';
import 'package:anywherellm/ui/chat/message_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
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
  testWidgets('an answer the relay goes on writing is not shown as a failure', (
    tester,
  ) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('And next quarter?');
    await tester.pump();
    llm.chat!.addError(const AnswerStillRunning());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Still being written'), findsOneWidget);
    expect(find.text('The answer stopped'), findsNothing);
    expect(h.chat.turns.last.unfinished, isTrue);
  });

  testWidgets('any other failure is', (tester) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('And next quarter?');
    await tester.pump();
    llm.chat!.addError(const ApiException('The server stopped the answer.'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('The answer stopped'), findsOneWidget);
    expect(find.text('Still being written'), findsNothing);
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
    ];
    await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    final answers = find.byType(AnswerBody);
    expect(answers, findsNWidgets(2));
    expect(
      tester.getTopLeft(answers.last).dx,
      tester.getTopLeft(answers.first).dx,
    );
  });

  testWidgets('a lost connection offers no Ask again', (tester) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('And next quarter?');
    await tester.pump();
    llm.chat!.addError(const AnswerStillRunning());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ask again'), findsNothing);
  });

  testWidgets('an answer found still running says it kept going', (
    tester,
  ) async {
    final llm = planningServer();
    // Closed below, not in a tear-down: one would wait on the test's fake clock, which no
    // longer runs then.
    final events = StreamController<ChatEvent>();
    llm.running['budget'] = (question: 'And next quarter?', events: events);
    // Held until the app has settled: a streaming answer's caret never lets it settle.
    final found = llm.gates['rejoinChat'] = Completer<void>();
    final h = await pumpApp(tester, llm: llm);
    found.complete();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Kept answering while the app was closed.'),
      findsOneWidget,
    );
    expect(h.chat.busy, isTrue);
    events
      ..add(const TextChunk('About 45k.'))
      ..add(const ChatDone([]));
    await events.close();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Kept answering while the app was closed.'), findsNothing);
    expect(find.text('About 45k.'), findsOneWidget);
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
}
