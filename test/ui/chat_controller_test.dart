import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';

import 'package:anywherellm/core/chat.dart';
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

  test('a draft whose first answer is stopped is still named', () async {
    final llm = planningServer()..hold = true;
    final rig = await started(llm);
    await rig.chat.select('household');
    await rig.chat.send('What bills are due this month?');
    await pumpEventQueue();
    rig.chat.stop();
    await pumpEventQueue();
    expect(rig.chat.title, 'What bills are due this month?');
  });

  test('a chat cleared and asked again keeps its name', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await rig.chat.send('/reset');
    await rig.chat.send('Something new entirely');
    await pumpEventQueue();
    expect(llm.calls.where((c) => c.startsWith('renameThread')), isEmpty);
    expect(rig.chat.title, 'Budget questions');
  });

  test('the turns a draft showed stay whole once its chat is made', () async {
    final llm = planningServer()..hold = true;
    final rig = await started(llm);
    await rig.chat.select('household');
    String? seen;
    rig.chat.addListener(() => seen = rig.chat.activeThread);
    final sending = rig.chat.send('hello');
    final shown = rig.chat.turns;
    await sending;
    expect(shown.map((t) => t.role), [Role.user, Role.assistant]);
    expect(seen, rig.chat.activeThread);
    expect(seen, isNotNull);
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

  test('an answer streams in, and only one runs in a workspace', () async {
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

  test('a failed answer says why and frees the chat', () async {
    final llm = planningServer()
      ..errors['streamChat'] = const ApiException('No LLM set');
    final rig = await started(llm);
    await rig.chat.send('hi');
    await pumpEventQueue();
    expect(rig.chat.turns.last.error, 'No LLM set');
    expect(rig.chat.busy, isFalse);
  });

  test('an image is read once, and again after a failed read', () async {
    final picture = Uri.parse('https://h:3001/pictures/a.png');
    final llm = planningServer()..errors['answerImage'] = Exception('down');
    final rig = await started(llm);
    await expectLater(rig.chat.bytes.image(picture), throwsException);
    llm
      ..errors.remove('answerImage')
      ..images[picture] = [1, 2, 3];
    expect(await rig.chat.bytes.image(picture), [1, 2, 3]);
    expect(await rig.chat.bytes.image(picture), [1, 2, 3]);
    expect(llm.calls.where((c) => c.startsWith('answerImage')), [
      'answerImage:$picture',
      'answerImage:$picture',
    ]);
  });

  group('refresh', () {
    test('reads the chat on screen again', () async {
      final llm = planningServer();
      final rig = await started(llm);
      llm.histories['budget'] = [
        ...llm.histories['budget']!,
        const ChatMessage(role: Role.user, text: 'Asked elsewhere'),
        const ChatMessage(role: Role.assistant, text: 'Answered elsewhere.'),
      ];
      await rig.chat.refresh();
      expect(rig.chat.turns.last.text, 'Answered elsewhere.');
      expect(rig.chat.refreshing, isFalse);
    });

    test('lets go of a stuck answer without stopping it', () async {
      final llm = planningServer()..hold = true;
      final rig = await started(llm);
      await rig.chat.send('And next quarter?');
      await rig.chat.refresh();
      expect(rig.chat.busy, isFalse);
      expect(rig.chat.turns.last.unfinished, isTrue);
      expect(rig.chat.turns.last.error, startsWith('Let go of'));
      expect(llm.chat!.hasListener, isFalse);

      // Once the server has saved it, the next refresh shows it.
      llm.histories['budget'] = [
        ...llm.histories['budget']!,
        const ChatMessage(role: Role.user, text: 'And next quarter?'),
        const ChatMessage(role: Role.assistant, text: 'About 45k.'),
      ];
      await rig.chat.refresh();
      expect(rig.chat.turns.last.text, 'About 45k.');
      expect(rig.chat.turns.last.error, isNull);
    });

    test('shows a chat cleared elsewhere', () async {
      final llm = planningServer();
      final rig = await started(llm);
      expect(rig.chat.turns, isNotEmpty);
      llm.histories['budget'] = const [];
      await rig.chat.refresh();
      expect(rig.chat.turns, isEmpty);
    });

    test('moves off a chat deleted elsewhere', () async {
      final llm = planningServer();
      final rig = await started(llm);
      expect(rig.chat.activeThread, 'budget');
      llm.spaces.first.threads.removeWhere((t) => t.slug == 'budget');
      llm.histories.remove('budget');
      await rig.chat.refresh();
      expect(rig.chat.activeThread, 'priorities');
      expect(rig.chat.problem, isNull);
    });

    test('a server back in reach is no longer a connection problem', () async {
      final llm = planningServer()
        ..errors['workspaces'] = const ApiException('Down');
      final rig = await started(llm);
      expect(rig.chat.unreachable.value, isTrue);
      llm.errors.remove('workspaces');
      await rig.chat.refresh();
      expect(rig.chat.unreachable.value, isFalse);
      expect(rig.chat.workspaces, isNotEmpty);
    });
  });

  test('a failed answer\'s chat is read again when it is opened', () async {
    final llm = planningServer()..hold = true;
    final rig = await started(llm);
    await rig.chat.send('And next quarter?');
    llm.chat!.addError(const ApiException('The answer was cut off.'));
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

  test('a failed answer\'s chat opened before the server saved it keeps the question', () async {
    final llm = planningServer()..hold = true;
    final rig = await started(llm);
    await rig.chat.send('And next quarter?');
    llm.chat!.addError(const ApiException('The answer was cut off.'));
    await pumpEventQueue();
    await rig.chat.open('priorities');
    await rig.chat.open('budget');
    expect(rig.chat.turns.map((t) => t.text), contains('And next quarter?'));
    expect(rig.chat.turns.last.unfinished, isTrue);
    llm.histories['budget'] = [
      ...llm.histories['budget']!,
      const ChatMessage(role: Role.user, text: 'And next quarter?'),
      const ChatMessage(role: Role.assistant, text: 'About 45k.'),
    ];
    await rig.chat.open('priorities');
    await rig.chat.open('budget');
    expect(rig.chat.turns.last.text, 'About 45k.');
  });

  test(
    'new chat while a draft\'s thread is made stays on the new draft',
    () async {
      final llm = planningServer()..gates['createThread'] = Completer<void>();
      final rig = await started(llm);
      rig.chat.newChat();
      final sending = rig.chat.send('First question');
      await pumpEventQueue();
      rig.chat.newChat();
      llm.gates['createThread']!.complete();
      await sending;
      expect(rig.chat.activeThread, isNull);
      expect(rig.chat.turns, isEmpty);
    },
  );

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

  test('an answer that names its exchange costs no read, and one that does not costs one', () async {
    final llm = planningServer();
    final rig = await started(llm);
    llm.calls.clear();
    await rig.chat.send('And next quarter?');
    await pumpEventQueue();
    expect(llm.calls.where((c) => c.startsWith('history')), isEmpty);

    llm.hold = true;
    await rig.chat.send('And the one after?');
    llm.chat!
      ..add(const TextChunk('Later.'))
      ..add(const ChatDone([]));
    await llm.chat!.close();
    await pumpEventQueue();
    expect(llm.calls.where((c) => c.startsWith('history')), [
      'history:${rig.chat.activeThread}',
    ]);
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

  test('new chat starts a draft while the chat on screen is read', () async {
    final llm = planningServer();
    final rig = await started(llm);
    final gate = llm.gates['history'] = Completer<void>();
    final opening = rig.chat.select('q3', thread: 'priorities');
    await pumpEventQueue();
    expect(rig.chat.turns, isEmpty);
    rig.chat.newChat();
    expect(rig.chat.activeThread, isNull);
    gate.complete();
    await opening;
  });

  test(
    'a chat tapped before the workspaces are read opens once they are',
    () async {
      final store = FakeSettingsStore()..saved = sampleConnection;
      final rig = Rig(
        llm: planningServer(),
        store: store,
        prefsStore: FakePrefsStore(
          const Prefs(lastChat: LastChat('household', null)),
        ),
      );
      addTearDown(rig.dispose);
      await rig.chat.openTapped('q3', 'priorities');
      await rig.prefs.load();
      await rig.settings.load();
      await pumpEventQueue();
      expect(
        (rig.chat.activeSlug, rig.chat.activeThread),
        ('q3', 'priorities'),
      );
    },
  );

  test('deleting the chat on screen shows a new chat in its place', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await rig.chat.delete('budget');
    expect(llm.calls, isNot(contains('deleteThread:budget')));
    expect(rig.chat.deletedChat, 'Budget questions');
    expect(rig.chat.activeThread, isNull);
    expect(rig.chat.activeSlug, 'q3');
    // A second delete sends the first.
    await rig.chat.open('priorities');
    await rig.chat.delete('priorities');
    expect(llm.calls, contains('deleteThread:budget'));
    expect(rig.chat.activeThread, isNull);
    expect(rig.chat.threadsOf('q3'), isEmpty);
    await rig.chat.flushDelete();
    expect(llm.calls, contains('deleteThread:priorities'));
    expect(rig.chat.deletedChat, isNull);
  });

  group('an answer ready', () {
    test('marks a chat whose answer ended while another showed', () async {
      final llm = planningServer()..hold = true;
      final rig = await started(llm);
      await rig.chat.send('And next quarter?');
      await rig.chat.open('priorities');
      await llm.chat!.close();
      await pumpEventQueue();
      expect(rig.chat.isReady('budget'), isTrue);
      expect(rig.chat.readyIn('q3'), isTrue);
      await rig.chat.open('budget');
      expect(rig.chat.isReady('budget'), isFalse);
      expect(rig.chat.readyIn('q3'), isFalse);
    });

    test('not when it ended on screen, failed or was stopped', () async {
      final llm = planningServer()..hold = true;
      final rig = await started(llm);
      await rig.chat.send('One');
      await llm.chat!.close();
      await pumpEventQueue();
      expect(rig.chat.isReady('budget'), isFalse);
      await rig.chat.send('Two');
      await rig.chat.open('priorities');
      llm.chat!.addError(const ApiException('No.'));
      await pumpEventQueue();
      expect(rig.chat.isReady('budget'), isFalse);
    });
  });

  group('undoing a delete', () {
    test('puts the chat back where it was, on screen again', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.chat.delete('budget');
      await rig.chat.undoDelete();
      expect(rig.chat.threadsOf('q3').map((t) => t.slug), [
        'priorities',
        'budget',
      ]);
      expect(rig.chat.activeThread, 'budget');
      expect(rig.chat.deletedChat, isNull);
      await rig.chat.flushDelete();
      expect(llm.calls, isNot(contains('deleteThread:budget')));
    });

    test('a new server sends the delete to the one it was made on', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.chat.delete('budget');
      await rig.settings.clear();
      await pumpEventQueue();
      expect(llm.calls, contains('deleteThread:budget'));
      expect(llm.deletedOn['budget']?.baseUrl, sampleConnection.baseUrl);
    });

    test('a delete the server refuses puts the chat back', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.chat.delete('priorities');
      llm.errors['deleteThread'] = const ApiException('No.');
      await rig.chat.flushDelete();
      expect(
        rig.chat.threadsOf('q3').map((t) => t.slug),
        contains('priorities'),
      );
      expect(rig.chat.problem?.title, 'Could not delete the chat');
    });
  });

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
    expect(llm.spaces.last.prompt, isNull);
  });

  test('a new workspace takes its instructions as typed', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await rig.chat.createWorkspace('Recipes', prompt: ' Answer as a chef.\n');
    expect(llm.spaces.last.prompt, ' Answer as a chef.\n');
    await rig.chat.createWorkspace('Blank', prompt: ' \n ');
    expect(llm.spaces.last.prompt, isNull);
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

  group('the last chat', () {
    test('opens at start, ahead of the person\'s order', () async {
      final rig = await started(
        planningServer(),
        prefs: const Prefs(
          workspaceOrder: ['household', 'q3'],
          lastChat: LastChat('q3', 'priorities'),
        ),
      );
      expect(rig.chat.activeSlug, 'q3');
      expect(rig.chat.activeThread, 'priorities');
    });

    test('opens its workspace\'s newest chat once it is gone', () async {
      final rig = await started(
        planningServer(),
        prefs: const Prefs(lastChat: LastChat('q3', 'deleted')),
      );
      expect(rig.chat.activeSlug, 'q3');
      expect(rig.chat.activeThread, 'budget');
    });

    test(
      'gives way to the person\'s order once its workspace is gone',
      () async {
        final rig = await started(
          planningServer(),
          prefs: const Prefs(
            workspaceOrder: ['household', 'q3'],
            lastChat: LastChat('deleted', 'priorities'),
          ),
        );
        expect(rig.chat.activeSlug, 'household');
      },
    );

    test('is saved on opening a chat, a draft and its first message', () async {
      final rig = await started(planningServer());
      final server = rig.chat.server!.baseUrl;
      expect(rig.prefsStore.saved.lastChat, LastChat('q3', 'budget', server));
      await rig.chat.select('q3', thread: 'priorities');
      expect(
        rig.prefsStore.saved.lastChat,
        LastChat('q3', 'priorities', server),
      );
      await rig.chat.select('q3', thread: 'budget');
      rig.chat.newChat();
      await pumpEventQueue();
      expect(rig.prefsStore.saved.lastChat, LastChat('q3', null, server));
      await rig.chat.send('hello');
      expect(
        rig.prefsStore.saved.lastChat,
        LastChat('q3', rig.chat.activeThread, server),
      );
      expect(rig.chat.activeThread, isNotNull);
    });

    test('follows a workspace whose slug changes', () async {
      final llm = planningServer()..renamedSlug = 'q4';
      final rig = await started(llm);
      await rig.chat.renameWorkspace('q3', 'Q4 planning');
      expect(rig.prefsStore.saved.lastChat?.slug, 'q4');
    });
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

  group('answers in several workspaces', () {
    /// Starts an answer in a new chat of Household, then shows Q3's budget chat.
    Future<Rig> householdAnswering(FakeAnythingLlm llm) async {
      llm.hold = true;
      final rig = await started(llm);
      await rig.chat.select('household');
      await rig.chat.send('Plan the meals');
      await pumpEventQueue();
      await rig.chat.select('q3', thread: 'budget');
      await pumpEventQueue();
      return rig;
    }

    test('run at once, each into its own chat', () async {
      final llm = planningServer();
      final rig = await householdAnswering(llm);
      final meals = llm.chats['th-1']!;
      expect(rig.chat.answeringIn('household'), isTrue);
      expect(rig.chat.busy, isFalse);
      expect(await rig.chat.send('And next quarter?'), isTrue);
      await pumpEventQueue();
      final budget = rig.chat.runningHere!;
      llm.chats['budget']!.add(const TextChunk('About 45k.'));
      meals.add(const TextChunk('Soup on Monday.'));
      await pumpEventQueue();
      expect(budget.text, 'About 45k.');
      expect(rig.chat.answeringIn('q3'), isTrue);
      expect(rig.chat.answeringIn('household'), isTrue);
      await rig.chat.select('household', thread: 'th-1');
      expect(rig.chat.runningHere!.text, 'Soup on Monday.');
    });

    test('stop stops only the chat on screen', () async {
      final llm = planningServer();
      final rig = await householdAnswering(llm);
      await rig.chat.send('And next quarter?');
      await pumpEventQueue();
      rig.chat.stop();
      await pumpEventQueue();
      expect(llm.chats['budget']!.hasListener, isFalse);
      expect(rig.chat.answeringIn('q3'), isFalse);
      expect(rig.chat.answeringIn('household'), isTrue);
      expect(llm.chats['th-1']!.hasListener, isTrue);
    });

    test('one that ends off screen is ready and its chat named', () async {
      final llm = planningServer();
      final rig = await householdAnswering(llm);
      llm.chats['th-1']!.add(const TextChunk('Soup on Monday.'));
      await llm.chats['th-1']!.close();
      await pumpEventQueue();
      expect(rig.chat.answeringIn('household'), isFalse);
      expect(rig.chat.isReady('th-1'), isTrue);
      expect(rig.chat.readyIn('household'), isTrue);
      expect(
        rig.chat.threadsOf('household').single.name,
        defaultTitle('Plan the meals'),
      );
    });

    test('a new server lets go of every one', () async {
      final llm = planningServer();
      final rig = await householdAnswering(llm);
      await rig.chat.send('And next quarter?');
      await pumpEventQueue();
      await rig.settings.clear();
      await pumpEventQueue();
      expect(llm.chats['th-1']!.hasListener, isFalse);
      expect(llm.chats['budget']!.hasListener, isFalse);
      expect(rig.chat.busy, isFalse);
    });
  });

  test('a new server starts afresh', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await rig.settings.clear();
    expect(rig.chat.workspaces, isEmpty);
    expect(rig.chat.activeSlug, isNull);
  });

  test('a late workspace list does not restore a forgotten server', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await pumpEventQueue();
    final gate = llm.gates['workspaces'] = Completer<void>();
    final loading = rig.chat.load();
    await rig.settings.clear();
    gate.complete();
    await loading;
    await pumpEventQueue();
    expect(rig.chat.workspaces, isEmpty);
    expect(rig.chat.threadsOf('q3'), isEmpty);
    expect(rig.chat.activeSlug, isNull);
    expect(rig.chat.loading, isFalse);
    expect(rig.chat.docCounts, isEmpty);
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
      expect(rig.prefs.offIn('household'), isEmpty);
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
        Attachment.of('photo.png', Uint8List(1)),
        Attachment.of('report.pdf', Uint8List(1)),
      ],
    );
    await pumpEventQueue();
    expect(llm.lastAttachments.map((a) => (a.name, a.mime)), [
      ('photo.png', 'image/png'),
      ('report.pdf', documentMime),
    ]);
    final question = rig.chat.turns[rig.chat.turns.length - 2];
    expect(question.attachments.map((a) => a.name), [
      'photo.png',
      'report.pdf',
    ]);
    expect(question.attachments.first.picture, hasLength(1));
    expect(question.attachments.last.picture, isNull);
  });

  test(
    'a message that starts with a slash goes to the server as typed',
    () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.chat.send('/reset');
      await pumpEventQueue();
      expect(llm.calls, contains('streamChat:budget:/reset'));
      expect(rig.chat.turns, hasLength(4));
    },
  );

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
          attachments: [Attachment.of('notes.md', utf8.encode('hi'))],
        );
        await pumpEventQueue();
        expect(rig.chat.canRetry, isFalse);
        await rig.chat.select('household');
        expect(rig.chat.canRetry, isFalse);
      },
    );
  });
}
