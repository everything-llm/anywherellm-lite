import 'dart:convert';
import 'dart:typed_data';
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

Future<Rig> started(
  FakeAnythingLlm llm, {
  Prefs prefs = const Prefs(),
  String? password,
  int? maxRuns,
}) async {
  final rig = Rig(
    llm: llm,
    connection: sampleConnection.withPassword(password),
    prefsStore: FakePrefsStore(prefs),
    maxRuns: maxRuns,
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

  test('a browser skill\'s own words take the place of its call\'s', () async {
    final llm = planningServer()..hold = true;
    final rig = await started(llm);
    await rig.chat.send('Fill it');
    final answer = rig.chat.turns.last;
    llm.chat!
      ..add(const StatusChunk('Typing into a field', tool: 'browser-act'))
      ..add(const StatusChunk('Filling in Customer name'));
    await pumpEventQueue();
    expect(answer.browsing, isTrue);
    expect(answer.status, 'Filling in Customer name');
    expect(answer.browserSteps, ['Filling in Customer name']);

    // Only the first line after a call is the skill's; another is not the browser's.
    llm.chat!.add(const StatusChunk('Loading glm-5.3 into memory'));
    await pumpEventQueue();
    expect(answer.browsing, isFalse);
    expect(answer.browserSteps, ['Filling in Customer name']);
  });

  test('a live card\'s repeated frame is given once', () async {
    final card = Uri.parse(
      'https://h:8445/_live/browser/bw-3aeecef2b460eeb7.jpg',
    );
    final live = StreamController<Uint8List>();
    final llm = planningServer()..liveImages[card] = live;
    final rig = await started(llm);
    final frames = rig.chat.imageFrames(card).toList();
    final one = Uint8List.fromList([1, 2, 3]);
    live
      ..add(one)
      ..add(Uint8List.fromList([1, 2, 3]))
      ..add(Uint8List.fromList([4, 5]));
    await live.close();
    expect(await frames, [
      [1, 2, 3],
      [4, 5],
    ]);
  });

  test(
    'a live card that ended after its repeated frame is read again',
    () async {
      final card = Uri.parse(
        'https://h:8445/_live/browser/bw-3aeecef2b460eeb7.jpg',
      );
      final live = StreamController<Uint8List>();
      final llm = planningServer()..liveImages[card] = live;
      final rig = await started(llm);
      final frames = rig.chat.imageFrames(card).toList();
      live
        ..add(Uint8List.fromList([1, 2, 3]))
        ..add(Uint8List.fromList([1, 2, 3]));
      await live.close();
      expect(await frames, [
        [1, 2, 3],
      ]);
      llm.calls.clear();
      final again = StreamController<Uint8List>();
      llm.liveImages[card] = again;
      final next = rig.chat.imageFrames(card).toList();
      again.add(Uint8List.fromList([4, 5]));
      await again.close();
      expect(await next, [
        [4, 5],
      ]);
      expect(llm.calls, ['answerImage:$card']);
    },
  );

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
      final thread = rig.chat.activeThread;
      await rig.chat.refresh();
      expect(rig.chat.busy, isFalse);
      expect(rig.chat.turns.last.unfinished, isTrue);
      expect(rig.chat.turns.last.error, startsWith('Let go of'));
      expect(llm.calls, isNot(contains('stopChat:$thread')));
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

  test('a failed answer\'s chat opened before the server saved it keeps the question', () async {
    final llm = planningServer()..hold = true;
    final rig = await started(llm);
    await rig.chat.send('And next quarter?');
    llm.chat!.addError(const ApiException('Lost the connection to the relay.'));
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

  group('an answer the relay kept going', () {
    StreamController<ChatEvent> running(
      FakeAnythingLlm llm, {
      String? question = 'And next quarter?',
    }) {
      final events = StreamController<ChatEvent>();
      llm.running['budget'] = (question: question, events: events);
      // Not waited for: closing a stream nobody followed never finishes.
      addTearDown(() => unawaited(events.close()));
      return events;
    }

    test('is followed again when its chat is opened', () async {
      final llm = planningServer();
      final events = running(llm);
      final rig = await started(llm);
      await pumpEventQueue();
      expect(rig.chat.busy, isTrue);
      expect(rig.chat.turns.map((t) => t.text), [
        'What is the budget?',
        'About 40k.',
        'And next quarter?',
        '',
      ]);
      expect(rig.chat.turns.last.rejoined, isTrue);
      expect(rig.chat.turns.last.streaming, isTrue);
      events
        ..add(const TextChunk('About '))
        ..add(const TextChunk('45k.'));
      await pumpEventQueue();
      expect(rig.chat.turns.last.text, 'About 45k.');
    });

    test('ends as any answer does, and the saved chat replaces it', () async {
      final llm = planningServer();
      final events = running(llm);
      final rig = await started(llm);
      await pumpEventQueue();
      final answer = rig.chat.turns.last;
      events.add(const TextChunk('About 45k.'));
      llm.histories['budget'] = [
        ...llm.histories['budget']!,
        const ChatMessage(
          role: Role.user,
          text: 'And next quarter?',
          chatId: 7,
        ),
        const ChatMessage(role: Role.assistant, text: 'About 45k.', chatId: 7),
      ];
      events.add(const ChatDone([]));
      await events.close();
      await pumpEventQueue();
      expect(rig.chat.busy, isFalse);
      expect(rig.chat.turns.last.text, 'About 45k.');
      expect(rig.chat.turns.last.rejoined, isFalse);
      expect(rig.chat.turns.last.chatId, 7);
      // The same turn, so what follows it, as Read aloud does, keeps it.
      expect(rig.chat.turns.last, same(answer));
    });

    test('keeps what came when the server has not saved it yet', () async {
      final llm = planningServer();
      final events = running(llm);
      final rig = await started(llm);
      await pumpEventQueue();
      events
        ..add(const TextChunk('About 45k.'))
        ..add(const ChatDone([], chatId: 9));
      await events.close();
      await pumpEventQueue();
      expect(rig.chat.busy, isFalse);
      expect(rig.chat.turns.last.text, 'About 45k.');
      expect(rig.chat.turns.last.chatId, 9);
    });

    test('is not followed in a chat whose history could not be read', () async {
      final llm = planningServer()
        ..errors['history'] = const ApiException('No.');
      running(llm);
      final rig = await started(llm);
      await pumpEventQueue();
      expect(rig.chat.busy, isFalse);
      expect(rig.chat.ready, isFalse);
    });

    test('is not followed once a message was sent meanwhile', () async {
      final llm = planningServer();
      running(llm);
      final found = llm.gates['rejoinChat'] = Completer<void>();
      final rig = await started(llm);
      await rig.chat.send('Something else?');
      await pumpEventQueue();
      found.complete();
      await pumpEventQueue();
      expect(rig.chat.turns.where((t) => t.rejoined), isEmpty);
      expect(
        rig.chat.turns.where((t) => t.text == 'And next quarter?'),
        isEmpty,
      );
    });

    test('is not asked about for a chat with nothing running', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await pumpEventQueue();
      expect(llm.calls, contains('rejoinChat:budget'));
      expect(rig.chat.busy, isFalse);
      expect(rig.chat.turns, hasLength(2));
    });

    test('takes the place of the answer the app lost touch with', () async {
      final llm = planningServer()..hold = true;
      final rig = await started(llm);
      await rig.chat.send('And next quarter?');
      llm.chat!.addError(const AnswerStillRunning());
      await pumpEventQueue();
      expect(rig.chat.turns.last.stillRunning, isTrue);
      final events = running(llm);
      await rig.chat.open('priorities');
      await rig.chat.open('budget');
      await pumpEventQueue();
      expect(
        rig.chat.turns.where((t) => t.text == 'And next quarter?'),
        hasLength(1),
      );
      expect(rig.chat.turns.last.rejoined, isTrue);
      expect(rig.chat.turns.last.error, isNull);
      expect(rig.chat.busy, isTrue);
      events.add(const TextChunk('About 45k.'));
      await pumpEventQueue();
      expect(rig.chat.turns.last.text, 'About 45k.');
    });

    test('can be stopped', () async {
      final llm = planningServer();
      running(llm);
      final rig = await started(llm);
      await pumpEventQueue();
      rig.chat.stop();
      await pumpEventQueue();
      expect(llm.calls, contains('stopChat:budget'));
      expect(rig.chat.busy, isFalse);
      expect(rig.chat.turns.last.stopped, isTrue);
    });

    test('with no question said, shows the answer alone', () async {
      final llm = planningServer();
      running(llm, question: null);
      final rig = await started(llm);
      await pumpEventQueue();
      expect(rig.chat.turns, hasLength(3));
      expect(rig.chat.turns.last.rejoined, isTrue);
    });

    test('a failed lookup does not fail the chat', () async {
      final llm = planningServer()
        ..errors['rejoinChat'] = const ApiException('No.');
      final rig = await started(llm);
      await pumpEventQueue();
      expect(rig.chat.problem, isNull);
      expect(rig.chat.turns, hasLength(2));
    });
  });

  group('a message refused as the chat is already answering', () {
    const refusal = AlreadyAnswering(
      'That thread already has an answer running.',
    );

    /// The answer running in the chat on another device, which the relay lists.
    StreamController<ChatEvent> elsewhere(FakeAnythingLlm llm) {
      final events = StreamController<ChatEvent>();
      llm.running['budget'] = (question: 'Asked on the phone', events: events);
      addTearDown(() => unawaited(events.close()));
      return events;
    }

    test('is given back, and the answer running is followed', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await pumpEventQueue();
      final events = elsewhere(llm);
      llm.errors['streamChat'] = refusal;
      final notes = Attachment.of('notes.txt', utf8.encode('Notes'));
      expect(
        await rig.chat.send('And a shorter one?', attachments: [notes]),
        isTrue,
      );
      await pumpEventQueue();
      expect(rig.chat.alreadyAnswering, isTrue);
      expect(rig.chat.problem, isNull);
      expect(rig.chat.turns.map((t) => t.text), [
        'What is the budget?',
        'About 40k.',
        'Asked on the phone',
        '',
      ]);
      final answer = rig.chat.turns.last;
      expect(answer.error, isNull);
      expect(answer.rejoined, isFalse);
      expect(rig.chat.runningHere, same(answer));
      final back = rig.chat.takeRefused()!;
      expect(back.text, 'And a shorter one?');
      expect(back.attachments.single.name, 'notes.txt');
      expect(rig.chat.takeRefused(), isNull);
      events.add(const TextChunk('Short.'));
      await events.close();
      await pumpEventQueue();
      expect(answer.text, 'Short.');
      expect(rig.chat.busy, isFalse);
      expect(rig.chat.alreadyAnswering, isFalse);
    });

    test('Stop stops the answer running', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await pumpEventQueue();
      elsewhere(llm);
      llm.errors['streamChat'] = refusal;
      await rig.chat.send('And a shorter one?');
      await pumpEventQueue();
      rig.chat.stop();
      await pumpEventQueue();
      expect(llm.calls, contains('stopChat:budget'));
      expect(rig.chat.busy, isFalse);
      expect(rig.chat.alreadyAnswering, isFalse);
      expect(rig.chat.turns.last.stopped, isTrue);
    });

    test('with nothing found running, can simply be sent again', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await pumpEventQueue();
      llm.errors['streamChat'] = refusal;
      await rig.chat.send('And a shorter one?');
      await pumpEventQueue();
      expect(rig.chat.alreadyAnswering, isFalse);
      expect(rig.chat.busy, isFalse);
      expect(rig.chat.turns, hasLength(2));
      expect(rig.chat.takeRefused()!.text, 'And a shorter one?');
    });

    test('is given back only in its own chat', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await pumpEventQueue();
      llm.errors['streamChat'] = refusal;
      await rig.chat.send('And a shorter one?');
      await pumpEventQueue();
      await rig.chat.open('priorities');
      expect(rig.chat.takeRefused(), isNull);
      await rig.chat.open('budget');
      expect(rig.chat.takeRefused(), isNull);
    });
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
      expect(llm.calls, isNot(contains('deleteThread:budget')));
      expect(rig.chat.deletedChat, 'Budget questions');
      expect(rig.chat.activeThread, 'priorities');
      // A second delete sends the first.
      await rig.chat.delete('priorities');
      expect(llm.calls, contains('deleteThread:budget'));
      expect(rig.chat.activeThread, isNull);
      expect(rig.chat.threadsOf('q3'), isEmpty);
      await rig.chat.flushDelete();
      expect(llm.calls, contains('deleteThread:priorities'));
      expect(rig.chat.deletedChat, isNull);
    },
  );

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
    Future<Rig> householdAnswering(FakeAnythingLlm llm, {int? maxRuns}) async {
      llm.hold = true;
      final rig = await started(llm, maxRuns: maxRuns);
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
      expect(llm.calls, contains('stopChat:budget'));
      expect(llm.calls, isNot(contains('stopChat:th-1')));
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

    test('at the limit, no other starts', () async {
      final llm = planningServer();
      final rig = await householdAnswering(llm, maxRuns: 1);
      expect(rig.chat.atLimit, isTrue);
      expect(rig.chat.busy, isTrue);
      expect(await rig.chat.send('And next quarter?'), isFalse);
      expect(llm.calls, isNot(contains('streamChat:budget:And next quarter?')));
      await llm.chats['th-1']!.close();
      await pumpEventQueue();
      expect(rig.chat.busy, isFalse);
    });

    test('a run the relay kept going is followed while another answers', () async {
      final llm = planningServer();
      final events = StreamController<ChatEvent>();
      addTearDown(() => unawaited(events.close()));
      llm.running['budget'] = (question: 'And next quarter?', events: events);
      final rig = await householdAnswering(llm);
      expect(rig.chat.runningHere, isNotNull);
      expect(rig.chat.turns.last.rejoined, isTrue);
      expect(rig.chat.answeringIn('household'), isTrue);
    });

    test('a refused message shows only in its own chat', () async {
      final llm = planningServer();
      final rig = await householdAnswering(llm);
      final events = StreamController<ChatEvent>();
      addTearDown(() => unawaited(events.close()));
      llm.running['budget'] = (question: 'Asked on the phone', events: events);
      llm.errors['streamChat'] = const AlreadyAnswering('Already answering.');
      await rig.chat.send('And a shorter one?');
      await pumpEventQueue();
      expect(rig.chat.alreadyAnswering, isTrue);
      await rig.chat.select('household', thread: 'th-1');
      expect(rig.chat.alreadyAnswering, isFalse);
      await rig.chat.select('q3', thread: 'budget');
      expect(rig.chat.alreadyAnswering, isTrue);
      await events.close();
      await pumpEventQueue();
      expect(rig.chat.alreadyAnswering, isFalse);
      expect(rig.chat.answeringIn('household'), isTrue);
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
          attachments: [Attachment.of('notes.md', utf8.encode('hi'))],
        );
        await pumpEventQueue();
        expect(rig.chat.canRetry, isFalse);
        await rig.chat.select('household');
        expect(rig.chat.canRetry, isFalse);
      },
    );
  });

  group('signed in', () {
    group('an answer that closes without its id', () {
      Future<(FakeAnythingLlm, Rig)> asked() async {
        final llm = withChatIds()
          ..omitsChatId = true
          ..answer = 'About 42k.';
        final rig = await started(llm, password: 'PASS-WORD');
        await rig.chat.send('And Q4?');
        await pumpEventQueue();
        return (llm, rig);
      }

      test('takes it from the history, and retry deletes by it', () async {
        final (llm, rig) = await asked();
        expect(rig.chat.turns.map((t) => t.chatId), [5, 5, 100, 100]);
        await rig.chat.retry();
        await pumpEventQueue();
        expect(llm.calls, contains('dropFrom:budget:100'));
      });

      test('takes none when the history read fails', () async {
        final llm = withChatIds()
          ..omitsChatId = true
          ..errors['history'] = const ApiException('no', status: 500);
        final rig = await started(llm, password: 'PASS-WORD');
        await rig.chat.select('household');
        await rig.chat.send('Bills?');
        await pumpEventQueue();
        expect(rig.chat.turns.map((t) => t.chatId), [null, null]);
      });

      test('retry reads the id first when it was not taken yet', () async {
        final llm = withChatIds()
          ..omitsChatId = true
          ..errors['history'] = const ApiException('no', status: 500);
        final rig = await started(llm, password: 'PASS-WORD');
        await rig.chat.select('household');
        await rig.chat.send('Bills?');
        await pumpEventQueue();
        llm.errors.remove('history');
        await rig.chat.retry();
        await pumpEventQueue();
        expect(llm.calls, contains('dropFrom:${rig.chat.activeThread}:100'));
      });

      Future<List<int?>> heldWith(List<ChatMessage> saved) async {
        final llm = withChatIds()..hold = true;
        final rig = await started(llm, password: 'PASS-WORD');
        await rig.chat.send('And Q4?');
        llm.histories['budget'] = [...llm.histories['budget']!, ...saved];
        llm.chat!
          ..add(const TextChunk('About 42k.'))
          ..add(const ChatDone([]));
        await llm.chat!.close();
        await pumpEventQueue();
        return [for (final t in rig.chat.turns) t.chatId];
      }

      test('takes none from a history whose last question differs', () async {
        expect(
          await heldWith(const [
            ChatMessage(role: Role.user, text: 'And Q1?', chatId: 6),
            ChatMessage(role: Role.assistant, text: 'About 42k.', chatId: 6),
          ]),
          [5, 5, null, null],
        );
      });

      test('takes none older than an id the chat has', () async {
        expect(
          await heldWith(const [
            ChatMessage(role: Role.user, text: 'And Q4?', chatId: 4),
            ChatMessage(role: Role.assistant, text: 'About 42k.', chatId: 4),
          ]),
          [5, 5, null, null],
        );
      });

      test('takes none for a stopped answer', () async {
        final llm = withChatIds()..hold = true;
        final rig = await started(llm, password: 'PASS-WORD');
        final reads = llm.calls.where((c) => c.startsWith('history')).length;
        await rig.chat.send('And Q4?');
        rig.chat.stop();
        await pumpEventQueue();
        expect(
          llm.calls.where((c) => c.startsWith('history')),
          hasLength(reads),
        );
      });

      test('takes none from an exchange saved after it', () async {
        final llm = withChatIds()..omitsChatId = true;
        final rig = await started(llm, password: 'PASS-WORD');
        final read = llm.gates['history'] = Completer<void>();
        await rig.chat.send('And Q4?');
        await pumpEventQueue();
        await rig.chat.send('And Q4?');
        await pumpEventQueue();
        read.complete();
        await pumpEventQueue();
        expect(rig.chat.turns.map((t) => t.chatId), [
          5,
          5,
          null,
          null,
          101,
          101,
        ]);
      });

      test('signed out, reads nothing', () async {
        final llm = withChatIds()
          ..omitsChatId = true
          ..auth = ServerAuth.password;
        final rig = await started(llm);
        await rig.settings.readAuth();
        final reads = llm.calls.where((c) => c.startsWith('history')).length;
        await rig.chat.send('And Q4?');
        await pumpEventQueue();
        expect(
          llm.calls.where((c) => c.startsWith('history')),
          hasLength(reads),
        );
      });
    });

    test('retry deletes the old exchange before asking again', () async {
      final llm = withChatIds()..answer = 'About 45k.';
      final rig = await started(llm, password: 'PASS-WORD');
      await rig.chat.retry();
      await pumpEventQueue();
      final asked = llm.calls.indexOf('streamChat:budget:What is the budget?');
      expect(
        llm.calls.indexOf('dropFrom:budget:5'),
        inInclusiveRange(0, asked),
      );
      expect(llm.histories['budget'], isEmpty);
      expect(rig.chat.turns.map((t) => t.text), [
        'What is the budget?',
        'About 45k.',
      ]);
      expect(rig.chat.turns.last.chatId, 100);
    });

    test('a delete that fails asks nothing again', () async {
      final llm = withChatIds()
        ..errors['dropFrom'] = const ApiException('no', status: 500);
      final rig = await started(llm, password: 'PASS-WORD');
      await rig.chat.retry();
      expect(llm.calls.where((c) => c.startsWith('streamChat:')), isEmpty);
      expect(rig.chat.problem?.title, 'Could not replace the old exchange');
      expect(rig.chat.turns, hasLength(2));
      expect(rig.chat.busy, isFalse);
    });

    test('signed out, retry deletes nothing', () async {
      final llm = withChatIds()..auth = ServerAuth.password;
      final rig = await started(llm);
      await rig.chat.retry();
      expect(llm.calls.where((c) => c.startsWith('dropFrom')), isEmpty);
    });

    test('an edited question replaces it and what came after', () async {
      final llm = withChatIds()..answer = 'About 50k.';
      final rig = await started(llm, password: 'PASS-WORD');
      rig.chat.edit(rig.chat.turns.first);
      expect(rig.chat.editing, same(rig.chat.turns.first));
      await rig.chat.send('What is the Q3 budget?');
      await pumpEventQueue();
      expect(llm.calls, contains('dropFrom:budget:5'));
      expect(rig.chat.editing, isNull);
      expect(rig.chat.turns.map((t) => t.text), [
        'What is the Q3 budget?',
        'About 50k.',
      ]);
    });

    test('signed out, editing only fills the composer', () async {
      final rig = await started(withChatIds()..auth = ServerAuth.password);
      rig.chat.edit(rig.chat.turns.first);
      expect(rig.chat.editing, isNull);
    });

    test(
      'a server with no password needs no sign-in to replace or mark',
      () async {
        final llm = withChatIds()..auth = ServerAuth.none;
        final rig = await started(llm);
        expect(rig.chat.signedIn, isFalse);
        await rig.settings.readAuth();
        expect(rig.chat.signedIn, isTrue);
        rig.chat.edit(rig.chat.turns.first);
        expect(rig.chat.editing, isNotNull);
      },
    );

    test(
      'retry while a question is being edited replaces only the last exchange',
      () async {
        final llm = withChatIds()..answer = 'About 45k.';
        llm.histories['budget'] = [
          ...llm.histories['budget']!,
          const ChatMessage(role: Role.user, text: 'And Q4?', chatId: 6),
          const ChatMessage(
            role: Role.assistant,
            text: 'About 42k.',
            chatId: 6,
          ),
        ];
        final rig = await started(llm, password: 'PASS-WORD');
        rig.chat.edit(rig.chat.turns.first);
        await rig.chat.retry();
        await pumpEventQueue();
        expect(llm.calls.where((c) => c.startsWith('dropFrom')), [
          'dropFrom:budget:6',
        ]);
        expect(rig.chat.editing, isNull);
        expect(rig.chat.turns.map((t) => t.text), [
          'What is the budget?',
          'About 40k.',
          'And Q4?',
          'About 45k.',
        ]);
      },
    );

    test('an edit whose old exchange cannot be deleted is not sent', () async {
      final llm = withChatIds()
        ..errors['dropFrom'] = const ApiException('no', status: 500);
      final rig = await started(llm, password: 'PASS-WORD');
      final question = rig.chat.turns.first;
      rig.chat.edit(question);
      final sent = await rig.chat.send('What is the Q3 budget?');
      expect(sent, isFalse);
      expect(rig.chat.editing, same(question));
      expect(llm.calls.where((c) => c.startsWith('streamChat:')), isEmpty);
      expect(rig.chat.problem?.title, 'Could not replace the old exchange');
    });

    test(
      'a delete that lands after the person moved on reads the chat afresh',
      () async {
        final llm = withChatIds()..gates['dropFrom'] = Completer<void>();
        final rig = await started(llm, password: 'PASS-WORD');
        final retrying = rig.chat.retry();
        await pumpEventQueue();
        await rig.chat.open('priorities');
        llm.gates['dropFrom']!.complete();
        await retrying;
        expect(llm.calls.where((c) => c.startsWith('streamChat:')), isEmpty);
        llm.calls.clear();
        await rig.chat.open('budget');
        expect(llm.calls, contains('history:budget'));
        expect(rig.chat.turns, isEmpty);
      },
    );

    test('new chat clears an edit', () async {
      final rig = await started(withChatIds(), password: 'PASS-WORD');
      rig.chat.edit(rig.chat.turns.first);
      rig.chat.newChat();
      expect(rig.chat.editing, isNull);
    });

    test('marks an answer, and a second tap clears it', () async {
      final llm = withChatIds();
      final rig = await started(llm, password: 'PASS-WORD');
      final answer = rig.chat.turns.last;
      await rig.chat.mark(answer, true);
      expect(answer.feedback, isTrue);
      await rig.chat.mark(answer, true);
      expect(answer.feedback, isNull);
      expect(llm.calls.where((c) => c.startsWith('setFeedback')), [
        'setFeedback:5:true',
        'setFeedback:5:null',
      ]);
    });

    test('a mark the server refuses goes back', () async {
      final llm = withChatIds()
        ..errors['setFeedback'] = const ApiException('no', status: 500);
      final rig = await started(llm, password: 'PASS-WORD');
      final answer = rig.chat.turns.last;
      await rig.chat.mark(answer, false);
      expect(answer.feedback, isNull);
      expect(rig.chat.problem?.title, 'Could not mark the answer');
    });

    test(
      'saving a password keeps the chat and lists the commands again',
      () async {
        final llm = withChatIds()
          ..errors['slashCommands'] = const ApiException('no', status: 401);
        final rig = await started(llm);
        await pumpEventQueue();
        final turns = rig.chat.turns;
        llm.errors.remove('slashCommands');
        await rig.settings.savePassword('PASS-WORD');
        await pumpEventQueue();
        expect(rig.chat.signedIn, isTrue);
        expect(rig.chat.turns, same(turns));
        expect(rig.chat.commandsNote, isNull);
        expect(llm.calls.where((c) => c == 'workspaces'), hasLength(1));
      },
    );

    test('a refused saved password says to replace it', () async {
      final llm = withChatIds()
        ..errors['slashCommands'] = const ApiException('no', status: 403);
      final rig = await started(llm, password: 'PASS-WORD');
      await pumpEventQueue();
      expect(rig.chat.commandsNote, contains('Replace it in Settings'));
    });
  });
}
