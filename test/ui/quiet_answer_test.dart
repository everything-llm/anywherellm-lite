import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/ui/state/turn.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

const _question = 'What is the budget for research?';

/// The app with [_question] sent and its answer held open, so a test feeds or starves it.
Future<(Harness, FakeAnythingLlm)> _asking(WidgetTester tester) async {
  final llm = planningServer()..hold = true;
  final h = await pumpApp(tester, llm: llm);
  await h.chat.send(_question);
  await tester.pump();
  return (h, llm);
}

final _noNews = find.textContaining('No news');

int _reads(FakeAnythingLlm llm) =>
    llm.calls.where((c) => c.startsWith('history')).length;

void main() {
  testWidgets('an answer with no news for 30 s says so, with Check and Stop', (
    tester,
  ) async {
    final (_, llm) = await _asking(tester);
    await tester.pump(const Duration(seconds: 29));
    expect(_noNews, findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.text('No news from the server for 30 seconds.'),
      findsOneWidget,
    );
    expect(control('Check'), findsOneWidget);
    // The card stands in the wait line's place.
    expect(find.textContaining('Asking'), findsNothing);
    await llm.chat!.close();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_noNews, findsNothing);
  });

  testWidgets('each piece of the answer starts the 30 s again', (tester) async {
    final (_, llm) = await _asking(tester);
    await tester.pump(const Duration(seconds: 20));
    llm.chat!.add(const TextChunk('About 40,000 kr'));
    await tester.pump(const Duration(seconds: 20));
    expect(_noNews, findsNothing);
    await tester.pump(const Duration(seconds: 11));
    // Under the words that came, which stay.
    expect(_noNews, findsOneWidget);
    expect(find.textContaining('About 40,000 kr'), findsOneWidget);
    await llm.chat!.close();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('Check with the server still at work leaves the answer running', (
    tester,
  ) async {
    final (h, llm) = await _asking(tester);
    await tester.pump(Turn.quietAfter);
    final before = _reads(llm);
    await tester.tap(control('Check'));
    await tester.pump();
    expect(_reads(llm), before + 1);
    expect(_noNews, findsNothing);
    expect(h.chat.answeringHere, isTrue);
    expect(h.chat.turns.last.waiting, isFalse);
    // Quiet again 30 s after the check.
    await tester.pump(Turn.quietAfter);
    expect(_noNews, findsOneWidget);
    llm.chat!.add(const TextChunk('Here it is.'));
    await llm.chat!.close();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Here it is.'), findsOneWidget);
  });

  testWidgets('Check with the server out of reach lets go of the answer', (
    tester,
  ) async {
    final (h, llm) = await _asking(tester);
    await tester.pump(Turn.quietAfter);
    llm.errors['history'] = const ApiException('Could not reach the server.');
    await tester.tap(control('Check'));
    await tester.pump();
    expect(h.chat.answeringHere, isFalse);
    expect(h.chat.turns.last.waiting, isTrue);
    expect(_noNews, findsNothing);

    llm.errors.remove('history');
    llm.saveExchange(h.chat.activeThread!, _question, 'Saved on the server.');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Saved on the server.'), findsOneWidget);
    expect(h.chat.working, isFalse);
  });

  testWidgets('Check with the answer already saved shows it', (tester) async {
    final (h, llm) = await _asking(tester);
    await tester.pump(Turn.quietAfter);
    llm.saveExchange(h.chat.activeThread!, _question, 'Saved meanwhile.');
    await tester.tap(control('Check'));
    await tester.pump();
    expect(h.chat.answeringHere, isFalse);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Saved meanwhile.'), findsOneWidget);
    expect(h.chat.working, isFalse);
  });

  testWidgets('a server that refuses the check is still there', (tester) async {
    final (h, llm) = await _asking(tester);
    await tester.pump(Turn.quietAfter);
    llm.errors['history'] = const ApiException('Refused', status: 500);
    await tester.tap(control('Check'));
    await tester.pump();
    expect(h.chat.answeringHere, isTrue);
    await llm.chat!.close();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('Stop on the card stops the answer', (tester) async {
    final (h, _) = await _asking(tester);
    await tester.pump(Turn.quietAfter);
    await tester.tap(control('Stop').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.chat.answeringHere, isFalse);
    expect(h.chat.turns.last.stopped, isTrue);
    expect(_noNews, findsNothing);
  });
}
