import 'dart:async';

import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/commands.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/server_models.dart';
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
      expect(rig.chat.turns.last.citations.map((c) => c.title), [
        'Q3 roadmap.pdf',
      ]);
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

    llm.chat!.add(const ChatDone([Citation('Q3 roadmap.pdf')]));
    await llm.chat!.close();
    await pumpEventQueue();
    expect(answer.streaming, isFalse);
    expect(answer.citations.map((c) => c.title), ['Q3 roadmap.pdf']);
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

  test('stop stops the answer on the server too', () async {
    final llm = planningServer()..hold = true;
    final rig = await started(llm);
    await rig.chat.send('one');
    final thread = rig.chat.activeThread;
    rig.chat.stop();
    await pumpEventQueue();
    expect(llm.calls, contains('stopChat:$thread'));
    expect(rig.chat.problem, isNull);
  });

  test('a stop the server refuses says the answer goes on there', () async {
    final llm = planningServer()
      ..hold = true
      ..errors['stopChat'] = const ApiException('Could not reach the relay.');
    final rig = await started(llm);
    await rig.chat.send('one');
    rig.chat.stop();
    await pumpEventQueue();
    expect(rig.chat.problem?.title, 'Could not stop the answer on the server');
    expect(rig.chat.busy, isFalse);
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

  test('a failed answer\'s chat is read again when it is opened', () async {
    final llm = planningServer()..hold = true;
    final rig = await started(llm);
    await rig.chat.send('And next quarter?');
    llm.chat!.addError(const ApiException('Lost the connection to the relay.'));
    await pumpEventQueue();
    llm.histories['budget'] = [
      ...llm.histories['budget']!,
      const ChatMessage(role: Role.user, text: 'And next quarter?'),
      const ChatMessage(role: Role.assistant, text: 'About 45k.'),
    ];
    await rig.chat.open('priorities');
    await rig.chat.open('budget');
    expect(rig.chat.turns.last.text, 'About 45k.');
    expect(rig.chat.turns.last.error, isNull);
  });

  test('a finished answer\'s chat is not read again', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await rig.chat.send('And next quarter?');
    await pumpEventQueue();
    await rig.chat.open('priorities');
    llm.calls.clear();
    await rig.chat.open('budget');
    expect(llm.calls.where((c) => c.startsWith('history')), isEmpty);
  });

  test('an agent answer shows its status, then its whole answer', () async {
    final llm = planningServer()..hold = true;
    final rig = await started(llm);
    await rig.chat.send('News?');
    final answer = rig.chat.turns.last;
    llm.chat!
      ..add(const TextChunk('<think>Plan</think>'))
      ..add(const StatusChunk('Running web-browsing'));
    await pumpEventQueue();
    expect(answer.status, 'Running web-browsing');
    llm.chat!
      ..add(const TextChunk('Draft'))
      ..add(const WholeAnswer('<think>Pick</think>Headline'))
      ..add(const ChatDone([Citation('A story')]));
    await llm.chat!.close();
    await pumpEventQueue();
    expect(answer.text, '<think>Pick</think>Headline');
    expect(answer.status, isNull);
    expect(answer.citations.map((c) => c.title), ['A story']);
    expect(answer.streaming, isFalse);
  });

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

  test('opens the first workspace in the person\'s order', () async {
    final rig = await started(
      planningServer(),
      prefs: const Prefs(workspaceOrder: ['household', 'q3']),
    );
    expect(rig.chat.activeSlug, 'household');
  });

  test('select can open a chat other than the newest', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await rig.chat.select('household');
    llm.calls.clear();
    await rig.chat.select('q3', thread: 'priorities');
    expect(rig.chat.activeThread, 'priorities');
    expect(llm.calls.where((c) => c.startsWith('history')), [
      'history:priorities',
    ]);
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
      expect(llm.calls.where((c) => c.startsWith('stopChat')), isEmpty);
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

  group('workspaces', () {
    test('a rename changes the name and keeps the chat on screen', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.chat.renameWorkspace('q3', ' Q4 planning ');
      expect(llm.calls, contains('renameWorkspace:q3:Q4 planning'));
      expect(rig.chat.active?.name, 'Q4 planning');
      expect(rig.chat.activeThread, 'budget');
      expect(rig.chat.threadsOf('q3'), hasLength(2));
    });

    test('a blank or unchanged name is not sent', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.chat.renameWorkspace('q3', '  ');
      await rig.chat.renameWorkspace('q3', 'Q3 planning');
      expect(llm.calls.where((c) => c.startsWith('renameWorkspace')), isEmpty);
    });

    test(
      'a rename that changes the slug keeps its place in the order',
      () async {
        final llm = planningServer()..renamedSlug = 'q4';
        final rig = await started(
          llm,
          prefs: const Prefs(workspaceOrder: ['q3', 'household']),
        );
        await rig.chat.renameWorkspace('q3', 'Q4 planning');
        expect(rig.prefs.prefs.workspaceOrder, ['q4', 'household']);
      },
    );

    test(
      'deleting the open workspace opens the first left in the order',
      () async {
        final llm = planningServer()
          ..spaces.add(FakeWorkspace('garden', 'Garden'));
        final rig = await started(
          llm,
          prefs: const Prefs(workspaceOrder: ['q3', 'garden', 'household']),
        );
        await rig.chat.deleteWorkspace('q3');
        expect(rig.chat.activeSlug, 'garden');
      },
    );

    test('a rename that changes the slug reads the workspaces again', () async {
      final llm = planningServer()..renamedSlug = 'q4';
      final rig = await started(llm);
      await rig.chat.renameWorkspace('q3', 'Q4 planning');
      expect(rig.chat.activeSlug, 'q4');
      expect(rig.chat.active?.name, 'Q4 planning');
      expect(rig.chat.threadsOf('q4'), hasLength(2));
    });

    test('a rename whose new list cannot be read says so', () async {
      final llm = planningServer()..renamedSlug = 'q4';
      final rig = await started(llm);
      llm.errors['workspaces'] = const ApiException('Down');
      await rig.chat.renameWorkspace('q3', 'Q4 planning');
      expect(rig.chat.problem?.title, 'Could not read the workspaces');
    });

    test('a refused rename becomes a notice', () async {
      final llm = planningServer()
        ..errors['renameWorkspace'] = const ApiException('Name taken');
      final rig = await started(llm);
      await rig.chat.renameWorkspace('q3', 'Q4 planning');
      expect(rig.chat.problem?.text, 'Name taken');
      expect(rig.chat.active?.name, 'Q3 planning');
    });

    test(
      'deleting the workspace on screen opens the first one left, then none',
      () async {
        final llm = planningServer();
        final rig = await started(llm);
        await rig.chat.deleteWorkspace('q3');
        expect(llm.calls, contains('deleteWorkspace:q3'));
        expect(rig.chat.workspaces.map((w) => w.slug), ['household']);
        expect(rig.chat.activeSlug, 'household');
        expect(rig.chat.threadsOf('q3'), isEmpty);
        await rig.chat.deleteWorkspace('household');
        expect(rig.chat.workspaces, isEmpty);
        expect(rig.chat.activeSlug, isNull);
      },
    );

    test('deleting another workspace leaves the screen alone', () async {
      final rig = await started(planningServer());
      await rig.chat.deleteWorkspace('household');
      expect(rig.chat.activeSlug, 'q3');
      expect(rig.chat.activeThread, 'budget');
    });

    test('a deleted workspace\'s switched-off files are forgotten', () async {
      final rig = await started(
        planningServer(),
        prefs: const Prefs(
          switchedOff: {
            'household': [OffDoc(path: 'custom-documents/a.json', title: 'a')],
          },
        ),
      );
      await rig.chat.deleteWorkspace('household');
      await pumpEventQueue();
      expect(rig.prefs.prefs.offIn('household'), isEmpty);
    });

    test('a workspace with an answer running cannot be deleted', () async {
      final llm = planningServer()..hold = true;
      final rig = await started(llm);
      await rig.chat.send('hi');
      expect(rig.chat.answeringIn('q3'), isTrue);
      await rig.chat.deleteWorkspace('q3');
      expect(llm.calls, isNot(contains('deleteWorkspace:q3')));
    });

    test('a refused delete becomes a notice', () async {
      final llm = planningServer()
        ..errors['deleteWorkspace'] = const ApiException('No');
      final rig = await started(llm);
      await rig.chat.deleteWorkspace('q3');
      expect(rig.chat.problem?.title, 'Could not delete the workspace');
      expect(rig.chat.workspaces, hasLength(2));
    });

    test(
      'a workspace delete that returns after a new server changes nothing',
      () async {
        final llm = planningServer();
        final rig = await started(llm);
        final gate = llm.gates['deleteWorkspace'] = Completer<void>();
        final deleting = rig.chat.deleteWorkspace('q3');
        await pumpEventQueue();
        await rig.settings.clear();
        gate.complete();
        await deleting;
        expect(rig.chat.workspaces, isEmpty);
        expect(rig.chat.activeSlug, isNull);
      },
    );
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

    test('a message sent while the chat is clearing is not sent', () async {
      final llm = planningServer();
      final rig = await started(llm);
      final gate = llm.gates['resetChat'] = Completer<void>();
      final clearing = rig.chat.send('/reset');
      await pumpEventQueue();
      expect(rig.chat.busy, isTrue);
      await rig.chat.send('Hello');
      expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
      gate.complete();
      await clearing;
      expect(rig.chat.busy, isFalse);
      expect(rig.chat.turns, isEmpty);
    });

    test('a new server while a chat clears leaves nothing busy', () async {
      final llm = planningServer();
      final rig = await started(llm);
      final gate = llm.gates['resetChat'] = Completer<void>();
      final clearing = rig.chat.send('/reset');
      await pumpEventQueue();
      expect(rig.chat.busy, isTrue);
      await rig.settings.clear();
      expect(rig.chat.busy, isFalse);
      llm.errors['resetChat'] = const ApiException('Gone');
      gate.complete();
      await clearing;
      expect(rig.chat.busy, isFalse);
      expect(rig.chat.problem, isNull);
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

  group('slash command note', () {
    test(
      'a password on the server says why its commands are missing',
      () async {
        final llm = planningServer()
          ..errors['slashCommands'] = const ApiException('no', status: 401);
        final rig = await started(llm);
        await pumpEventQueue();
        expect(rig.chat.commandsNote, contains('has a password'));
        expect(rig.chat.commands.map((c) => c.command), ['/reset']);
      },
    );

    test('another failure says only that they could not be listed', () async {
      final llm = planningServer()
        ..errors['slashCommands'] = const ApiException('down', status: 500);
      final rig = await started(llm);
      await pumpEventQueue();
      expect(rig.chat.commandsNote, contains('could not be listed'));
    });

    test(
      'a server that lists them has no note, and a new server clears it',
      () async {
        final llm = planningServer()
          ..errors['slashCommands'] = const ApiException('no', status: 401);
        final rig = await started(llm);
        await pumpEventQueue();
        llm.errors.remove('slashCommands');
        await rig.settings.save('https://other:3001', 'K2');
        await pumpEventQueue();
        expect(rig.chat.commandsNote, isNull);
      },
    );
  });

  group('retry', () {
    test('asks the last question again in place of its answer', () async {
      final llm = planningServer()..answer = 'About 45k.';
      final rig = await started(llm);
      expect(rig.chat.canRetry, isTrue);
      await rig.chat.retry();
      await pumpEventQueue();
      expect(llm.calls, contains('streamChat:budget:What is the budget?'));
      expect(rig.chat.turns.map((t) => t.text), [
        'What is the budget?',
        'About 45k.',
      ]);
    });

    test('is off while an answer runs', () async {
      final llm = planningServer()..hold = true;
      final rig = await started(llm);
      await rig.chat.send('Summarise');
      expect(rig.chat.canRetry, isFalse);
      await rig.chat.retry();
      expect(llm.calls.where((c) => c.startsWith('streamChat:')), hasLength(1));
    });

    test(
      'is off for a question sent with files, and for an empty chat',
      () async {
        final rig = await started(planningServer());
        await rig.chat.send(
          'What is in this?',
          attachments: [Attachment.of('notes.md', 'hi'.codeUnits)],
        );
        await pumpEventQueue();
        expect(rig.chat.canRetry, isFalse);
        await rig.chat.select('household');
        expect(rig.chat.canRetry, isFalse);
      },
    );
  });
}
