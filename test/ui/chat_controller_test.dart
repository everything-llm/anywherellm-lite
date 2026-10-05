import 'package:everything/core/chat.dart';
import 'package:everything/core/ports.dart';
import 'package:everything/core/prefs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
import '../support/rig.dart';

Future<Rig> started(FakeAnythingLlm llm, {Prefs prefs = const Prefs()}) async {
  final rig = Rig(
    llm: llm,
    connection: sampleConnection,
    prefsStore: FakePrefsStore(prefs),
  );
  addTearDown(rig.dispose);
  await rig.start();
  return rig;
}

void main() {
  test(
    'opens the first workspace on its newest chat, with its history',
    () async {
      final rig = await started(planningServer());
      expect(rig.chat.activeSlug, 'q3');
      expect(rig.chat.activeThread, 'budget');
      expect(rig.chat.title, 'Budget questions');
      expect(rig.chat.turns.map((t) => t.text), [
        'What is the budget?',
        'About 40k.',
      ]);
      expect(rig.chat.turns.last.citations, ['Q3 roadmap.pdf']);
    },
  );

  test('counts each workspace\'s documents', () async {
    final rig = await started(planningServer());
    await pumpEventQueue();
    expect(rig.chat.docCounts, {'q3': 2, 'household': 0});
  });

  test('a workspace with no chats opens on a draft', () async {
    final rig = await started(planningServer());
    await rig.chat.select('household');
    expect(rig.chat.activeThread, isNull);
    expect(rig.chat.title, newChatName);
    expect(rig.chat.turns, isEmpty);
  });

  test('the first message of a draft makes its thread and names it', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await rig.chat.select('household');
    await rig.chat.send('What bills are due this month?');
    await pumpEventQueue();
    expect(llm.calls, contains('createThread:household'));
    final thread = rig.chat.activeThread!;
    expect(rig.chat.title, 'What bills are due this month?');
    expect(rig.chat.threadsOf('household').single.slug, thread);
    expect(rig.chat.turns.map((t) => t.text), [
      'What bills are due this month?',
      'Here is what your sources say.',
    ]);
    expect(rig.chat.busy, isFalse);
  });

  test(
    'a chat the person named keeps its name after the first answer',
    () async {
      final llm = planningServer()..hold = true;
      final rig = await started(llm);
      await rig.chat.select('household');
      await rig.chat.send('hello');
      final thread = rig.chat.activeThread!;
      await rig.chat.rename(thread, 'Bills');
      llm.chat!
        ..add(const TextChunk('hi'))
        ..add(const ChatDone([]));
      await llm.chat!.close();
      await pumpEventQueue();
      expect(rig.chat.title, 'Bills');
    },
  );

  test('an answer streams in, and only one runs at a time', () async {
    final llm = planningServer()..hold = true;
    final rig = await started(llm);
    await rig.chat.send('Summarise');
    expect(rig.chat.answeringHere, isTrue);
    final answer = rig.chat.turns.last;
    expect(answer.streaming, isTrue);

    llm.chat!.add(const TextChunk('Part one'));
    await pumpEventQueue();
    expect(answer.text, 'Part one');

    await rig.chat.open('priorities');
    expect(rig.chat.busy, isTrue);
    expect(rig.chat.answeringHere, isFalse);
    await rig.chat.send('another');
    expect(llm.calls.where((c) => c.startsWith('streamChat')), hasLength(1));

    llm.chat!.add(const ChatDone(['Q3 roadmap.pdf']));
    await llm.chat!.close();
    await pumpEventQueue();
    expect(answer.streaming, isFalse);
    expect(answer.citations, ['Q3 roadmap.pdf']);
    expect(rig.chat.busy, isFalse);
  });

  test('stop keeps what came, or says Stopped when nothing did', () async {
    final llm = planningServer()..hold = true;
    final rig = await started(llm);
    await rig.chat.send('one');
    rig.chat.stop();
    expect(rig.chat.turns.last.text, 'Stopped.');
    expect(rig.chat.busy, isFalse);

    await rig.chat.send('two');
    llm.chat!.add(const TextChunk('Half'));
    await pumpEventQueue();
    rig.chat.stop();
    expect(rig.chat.turns.last.text, 'Half');
  });

  test('a failed answer says why and frees the chat', () async {
    final llm = planningServer()
      ..errors['streamChat'] = const ApiException('No LLM set');
    final rig = await started(llm);
    await rig.chat.send('hi');
    await pumpEventQueue();
    expect(rig.chat.turns.last.error, 'No LLM set');
    expect(rig.chat.busy, isFalse);
  });

  test(
    'answers only from documents unless general answers are allowed',
    () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.chat.send('a');
      await pumpEventQueue();
      await rig.prefs.setGroundedOnly(false);
      await rig.chat.send('b');
      await pumpEventQueue();
      expect(llm.modes, [ChatMode.query, ChatMode.chat]);
    },
  );

  test('new chat starts a draft, unless the chat is already empty', () async {
    final rig = await started(planningServer());
    rig.chat.newChat();
    expect(rig.chat.activeThread, isNull);
    rig.chat.newChat();
    expect(rig.chat.activeThread, isNull);
  });

  test(
    'deleting the chat on screen shows the one beside it, then a draft',
    () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.chat.delete('budget');
      expect(llm.calls, contains('deleteThread:budget'));
      expect(rig.chat.activeThread, 'priorities');
      await rig.chat.delete('priorities');
      expect(rig.chat.activeThread, isNull);
      expect(rig.chat.threadsOf('q3'), isEmpty);
    },
  );

  test('a chat that is answering cannot be deleted', () async {
    final llm = planningServer()..hold = true;
    final rig = await started(llm);
    await rig.chat.send('hi');
    await rig.chat.delete('budget');
    expect(llm.calls, isNot(contains('deleteThread:budget')));
  });

  test('a new workspace is made and opened', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await rig.chat.createWorkspace('  Reading notes ');
    expect(llm.calls, contains('createWorkspace:Reading notes'));
    expect(rig.chat.active!.name, 'Reading notes');
    expect(rig.chat.activeThread, isNull);
  });

  test('a failure becomes a notice', () async {
    final llm = planningServer()
      ..errors['renameThread'] = const ApiException('locked');
    final rig = await started(llm);
    await rig.chat.rename('budget', 'Money');
    expect(rig.chat.problem!.text, 'locked');
    expect(rig.chat.title, 'Budget questions');
  });

  test('a new server starts afresh', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await rig.settings.clear();
    expect(rig.chat.workspaces, isEmpty);
    expect(rig.chat.activeSlug, isNull);
  });
}
