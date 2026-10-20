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
    changed: () {},
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
    await tester.pump(const Duration(seconds: 5));
    expect(_reads(llm), 1);
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
}
