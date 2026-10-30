import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/ui/state/answer_waits.dart';
import 'package:anywherellm/ui/state/turn.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

/// An [AnswerWaits] over [llm] that shows [turns] by chat, and the histories it took.
(AnswerWaits, List<List<Turn>>) _waits(
  FakeAnythingLlm llm,
  Map<String, List<Turn>> turns,
) {
  final saved = <List<Turn>>[];
  final waits = AnswerWaits(
    llm,
    turnsOf: (thread) => turns[thread],
    saved: (slug, thread, now) {
      turns[thread] = now;
      saved.add(now);
    },
    changed: (_) {},
  );
  return (waits, saved);
}

int _reads(FakeAnythingLlm llm) =>
    llm.calls.where((c) => c.startsWith('history')).length;

void main() {
  testWidgets('a second wait in a chat ends the first and its timer', (
    tester,
  ) async {
    final llm = FakeAnythingLlm();
    final first = Turn.answer();
    final second = Turn.answer();
    final turns = {
      't': [Turn.user('one'), first, Turn.user('two'), second],
    };
    final (waits, _) = _waits(llm, turns);
    waits.start(first, 's', 't', after: 1);
    waits.start(second, 's', 't', after: 1);
    expect(first.waiting, isFalse);
    expect(first.error, isNotNull);
    expect(second.waiting, isTrue);
    // Each wait reads the chat at once; after that only the second reads again.
    await tester.pump();
    final atOnce = _reads(llm);
    await tester.pump(const Duration(seconds: 5));
    expect(_reads(llm), atOnce + 1);
    waits.clear();
  });

  testWidgets('a read that fails oddly is read again', (tester) async {
    final llm = FakeAnythingLlm();
    final answer = Turn.answer();
    final turns = {
      't': [Turn.user('Q?'), answer],
    };
    final (waits, saved) = _waits(llm, turns);
    waits.start(answer, 's', 't', after: 1);
    llm.errors['history'] = StateError('odd');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(answer.waiting, isTrue);
    expect(waits.has('t'), isTrue);

    llm.errors.remove('history');
    llm.saveExchange('t', 'Q?', 'A.', chatId: 2);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(saved, hasLength(1));
    expect(answer.waiting, isFalse);
    expect(waits.any, isFalse);
  });

  testWidgets('Check now with a read that fails oddly keeps the wait', (
    tester,
  ) async {
    final llm = FakeAnythingLlm();
    final answer = Turn.answer();
    final turns = {
      't': [Turn.user('Q?'), answer],
    };
    final (waits, _) = _waits(llm, turns);
    waits.start(answer, 's', 't', after: 1);
    llm.errors['history'] = StateError('odd');
    await waits.checkAll();
    expect(waits.has('t'), isTrue);
    expect(answer.waiting, isTrue);
    waits.clear();
  });

  testWidgets('a read that reaches the server says it is still answering', (
    tester,
  ) async {
    final llm = FakeAnythingLlm()
      ..errors['history'] = const ApiException('Could not reach the server.');
    final answer = Turn.answer();
    final turns = {
      't': [Turn.user('Q?'), answer],
    };
    final (waits, _) = _waits(llm, turns);
    waits.start(answer, 's', 't', after: 1);
    await tester.pump();
    expect(answer.dropped, Dropped.lost);
    llm.errors.remove('history');
    await tester.pump(const Duration(seconds: 5));
    expect(answer.dropped, Dropped.answering);
    llm.errors['history'] = const ApiException('Could not reach the server.');
    await tester.pump(const Duration(seconds: 5));
    expect(answer.dropped, Dropped.lost);
    waits.clear();
  });

  for (final (finishes, cut) in [(false, true), (true, false), (null, false)]) {
    testWidgets(
      'an answer saved after the drop ${cut ? 'may be' : 'is not'} cut '
      'short when the server ${switch (finishes) {
        true => 'finishes it',
        false => 'stops it',
        null => 'is not known to finish it',
      }}',
      (tester) async {
        final llm = FakeAnythingLlm()..saveExchange('t', 'Q?', 'A.', chatId: 2);
        final answer = Turn.answer();
        final turns = {
          't': [Turn.user('Q?'), answer],
        };
        final (waits, saved) = _waits(llm, turns);
        waits.start(answer, 's', 't', after: 1, finishes: finishes);
        await tester.pump();
        expect(saved.single.last.text, 'A.');
        expect(saved.single.last.mayBeCut, cut);
      },
    );
  }
}
