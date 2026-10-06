import 'dart:async';

import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/commands.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/prefs.dart';
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

  test(
    'Stop while a draft\'s chat is made keeps the chat and runs no answer',
    () async {
      final llm = planningServer()..hold = true;
      final rig = await started(llm);
      await rig.chat.select('household');
      final gate = llm.gates['createThread'] = Completer<void>();
      final sending = rig.chat.send('hi');
      await pumpEventQueue();
      rig.chat.stop();
      gate.complete();
      await sending;
      expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
      expect(rig.chat.busy, isFalse);
      expect(rig.chat.threadsOf('household'), hasLength(1));
      expect(rig.chat.turns.last.text, 'Stopped.');
    },
  );

  test('a new server while a draft\'s chat is made drops the chat', () async {
    final llm = planningServer()..hold = true;
    final rig = await started(llm);
    await rig.chat.select('household');
    final gate = llm.gates['createThread'] = Completer<void>();
    final sending = rig.chat.send('hi');
    await pumpEventQueue();
    await rig.settings.save('https://other:3001', 'K2');
    await pumpEventQueue();
    gate.complete();
    await sending;
    await pumpEventQueue();
    expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
    expect(rig.chat.threadsOf('household'), isEmpty);
    expect(rig.chat.busy, isFalse);
  });

  test('a chat whose history is still being read takes no message', () async {
    final llm = planningServer();
    final rig = await started(llm);
    final gate = llm.gates['history'] = Completer<void>();
    final opening = rig.chat.open('priorities');
    expect(rig.chat.ready, isFalse);
    await rig.chat.send('hi');
    expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
    gate.complete();
    await opening;
    expect(rig.chat.ready, isTrue);
    expect(rig.chat.turns, isEmpty);
  });

  test('a delete that returns after a new server changes nothing', () async {
    final llm = planningServer();
    final rig = await started(llm);
    final gate = llm.gates['deleteThread'] = Completer<void>();
    final deleting = rig.chat.delete('budget');
    await pumpEventQueue();
    await rig.settings.clear();
    gate.complete();
    await deleting;
    expect(rig.chat.workspaces, isEmpty);
  });

  test('attachments go with the message and their names stay on it', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await rig.chat.send(
      'What is in these?',
      attachments: [
        Attachment.of('photo.png', const [1]),
        Attachment.of('report.pdf', const [2]),
      ],
    );
    await pumpEventQueue();
    expect(llm.lastAttachments.map((a) => (a.name, a.mime)), [
      ('photo.png', 'image/png'),
      ('report.pdf', documentMime),
    ]);
    final question = rig.chat.turns[rig.chat.turns.length - 2];
    expect(question.attachments, ['photo.png', 'report.pdf']);
  });

  group('slash commands', () {
    const clear = SlashCommand(command: '/clear', prompt: '/reset');

    test('offers /reset, then the server\'s presets', () async {
      final llm = planningServer()..presets = const [clear];
      final rig = await started(llm);
      await pumpEventQueue();
      expect(
        [for (final c in rig.chat.commands) c.command],
        ['/reset', '/clear'],
      );
    });

    test('presets that cannot be read leave /reset alone', () async {
      final llm = planningServer()
        ..errors['slashCommands'] = const ApiException('No login');
      final rig = await started(llm);
      await pumpEventQueue();
      expect(rig.chat.problem, isNull);
      expect([for (final c in rig.chat.commands) c.command], ['/reset']);
    });

    test('/reset clears the chat on the server and on screen', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.chat.send('/reset');
      expect(llm.calls, contains('resetChat:budget'));
      expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
      expect(rig.chat.turns, isEmpty);
      expect(rig.chat.threadsOf('q3').map((t) => t.name), [
        'Quarter priorities',
        'Budget questions',
      ]);
    });

    test('a preset whose prompt is /reset clears the chat too', () async {
      final llm = planningServer()..presets = const [clear];
      final rig = await started(llm);
      await pumpEventQueue();
      await rig.chat.send('/clear');
      expect(llm.calls, contains('resetChat:budget'));
      expect(rig.chat.turns, isEmpty);
    });

    test('a failed reset keeps the turns and says why', () async {
      final llm = planningServer()
        ..errors['resetChat'] = const ApiException('Refused');
      final rig = await started(llm);
      await rig.chat.send('/reset');
      expect(rig.chat.turns, hasLength(2));
      expect(rig.chat.problem?.title, 'Could not clear the chat');
    });

    test('/reset in a draft only empties it, making no thread', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.chat.select('household');
      await rig.chat.send('/reset');
      expect(llm.calls, isNot(contains('createThread:household')));
      expect(llm.calls.where((c) => c.startsWith('resetChat')), isEmpty);
      expect(rig.chat.turns, isEmpty);
    });

    test('any other preset goes to the server as typed', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.chat.send('/deep-research tides');
      await pumpEventQueue();
      expect(llm.calls, contains('streamChat:budget:/deep-research tides'));
    });
  });
}
