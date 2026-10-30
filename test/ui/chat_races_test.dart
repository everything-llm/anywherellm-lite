import 'dart:async';

import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/core/shortcuts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/rig.dart';

const _dropped = CutOff('The connection dropped');
const _use = ShortcutUse(label: 'Summarise', detail: 'Summarise this.');

Future<Rig> _started(FakeAnythingLlm llm) async {
  final rig = Rig(llm: llm, connection: sampleConnection);
  addTearDown(rig.dispose);
  await rig.start();
  return rig;
}

/// Chat `budget` with one exchange the server saved as exchange 5.
FakeAnythingLlm _server() => planningServer()
  ..histories['budget'] = const [
    ChatMessage(role: Role.user, text: 'What is the budget?', chatId: 5),
    ChatMessage(role: Role.assistant, text: 'About 40k.', chatId: 5),
  ];

void main() {
  group('a history read that comes back late', () {
    test(
      'does not replace the turns of an answer that settled meanwhile',
      () async {
        final llm = _server();
        final rig = await _started(llm);
        final gate = llm.gates['history'] = Completer<void>();
        final reading = rig.chat.open('budget', again: true);
        await pumpEventQueue();
        await rig.chat.send('And next year?');
        await pumpEventQueue();
        gate.complete();
        await reading;
        expect(rig.chat.turns.map((t) => t.text), contains('And next year?'));
        expect(rig.chat.turns.length, 4);
      },
    );

    testWidgets('does not move the newest exchange back', (tester) async {
      final llm = _server();
      final rig = await _started(llm);
      final gate = llm.gates['history'] = Completer<void>();
      final reading = rig.chat.open('budget', again: true);
      await tester.pump();
      await rig.chat.send('And next year?');
      await tester.pump();
      gate.complete();
      await reading;
      // A later answer drops; the server's history still ends in the answer before it.
      llm.hold = true;
      await rig.chat.send('And the year after?');
      await tester.pump();
      llm.chat!.addError(_dropped);
      await tester.pump();
      llm.saveExchange('budget', 'And next year?', 'About 45k.', chatId: 100);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(rig.chat.turns.last.waiting, isTrue);
      await tester.pump(const Duration(minutes: 40));
    });
  });

  group('Retry', () {
    test('keeps the shortcut its question was sent with', () async {
      final rig = await _started(planningServer());
      await rig.chat.send('Summarise this.', shortcutUse: _use);
      await pumpEventQueue();
      await rig.chat.retry();
      final question = rig.chat.turns[rig.chat.turns.length - 2];
      expect(question.shortcutUse, _use);
    });
  });

  group('a shortcut use', () {
    test(
      'is remembered for an agent answer, whose closing chunk has no id',
      () async {
        final llm = planningServer()..hold = true;
        final rig = await _started(llm);
        await rig.chat.send('Summarise this.', shortcutUse: _use);
        final thread = rig.chat.activeThread!;
        llm.saveExchange(thread, 'Summarise this.', 'Done.', chatId: 7);
        llm.chat!
          ..add(const TextChunk('Done.'))
          ..add(const ChatDone([]));
        await llm.chat!.close();
        await pumpEventQueue();
        await pumpEventQueue();
        expect(rig.prefs.shortcutUse('q3', thread, 7)?.label, 'Summarise');
      },
    );
  });

  group('a refresh', () {
    test(
      'holds the messages waiting in another chat whose answer fails meanwhile',
      () async {
        final llm = _server()..hold = true;
        final rig = await _started(llm);
        await rig.chat.send('And next year?');
        expect(rig.chat.sendWhenDone('And the year after?'), isTrue);
        await rig.chat.open('priorities');
        final gate = llm.gates['workspaces'] = Completer<void>();
        final refreshing = rig.chat.refresh();
        await pumpEventQueue();
        llm.chats['budget']!.addError(const ApiException('The model failed.'));
        await pumpEventQueue();
        gate.complete();
        await refreshing;
        await pumpEventQueue();
        expect(
          llm.calls,
          isNot(contains('streamChat:budget:And the year after?')),
        );
        await rig.chat.open('budget');
        expect(rig.chat.onDeckHeld, isTrue);
      },
    );
  });

  group('a chat being cleared', () {
    test('sends on the messages resumed meanwhile once it is clear', () async {
      final llm = _server()..hold = true;
      final rig = await _started(llm);
      await rig.chat.send('And next year?');
      expect(rig.chat.sendWhenDone('Kept'), isTrue);
      rig.chat.stop();
      expect(rig.chat.onDeckHeld, isTrue);
      final gate = llm.gates['resetChat'] = Completer<void>();
      final clearing = rig.chat.reset();
      await pumpEventQueue();
      rig.chat.resumeOnDeck();
      expect(llm.calls, isNot(contains('streamChat:budget:Kept')));
      gate.complete();
      await clearing;
      expect(llm.calls, contains('streamChat:budget:Kept'));
    });
  });

  group('a draft', () {
    test('stopped while its thread is made is still named', () async {
      final llm = planningServer();
      final rig = await _started(llm);
      await rig.chat.select('household');
      final gate = llm.gates['createThread'] = Completer<void>();
      final sending = rig.chat.send('What bills are due?');
      await pumpEventQueue();
      rig.chat.stop();
      gate.complete();
      await sending;
      await pumpEventQueue();
      expect(llm.calls.where((c) => c.startsWith('renameThread')), [
        'renameThread:th-1:What bills are due?',
      ]);
      expect(
        rig.chat.threadsOf('household').single.name,
        'What bills are due?',
      );
      expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
    });

    test('a refresh while its thread is made still sends it', () async {
      final llm = planningServer();
      final rig = await _started(llm);
      await rig.chat.select('household');
      final gate = llm.gates['createThread'] = Completer<void>();
      final sending = rig.chat.send('What bills are due?');
      await pumpEventQueue();
      await rig.chat.refresh();
      gate.complete();
      await sending;
      await pumpEventQueue();
      expect(llm.calls, contains('streamChat:th-1:What bills are due?'));
      expect(rig.chat.turns.last.error, isNull);
      expect(rig.chat.turns.last.text, llm.answer);
    });

    test(
      'keeps its thread when the workspaces were read before it was made',
      () async {
        final llm = planningServer();
        final rig = await _started(llm);
        await rig.chat.select('household');
        final gate = llm.gates['workspaces'] = Completer<void>();
        final loading = rig.chat.load();
        await pumpEventQueue();
        await rig.chat.send('hello');
        await pumpEventQueue();
        final thread = rig.chat.activeThread!;
        // The read began before the thread was made, so the server's list in it lacks the thread.
        llm.spaces.last.threads.clear();
        gate.complete();
        await loading;
        await pumpEventQueue();
        expect(rig.chat.threadsOf('household').map((t) => t.slug), [thread]);
        expect(rig.chat.title, 'hello');
      },
    );
  });

  group('a workspace deleted', () {
    testWidgets('takes the chat waiting to be deleted with it', (tester) async {
      final llm = planningServer();
      final rig = await _started(llm);
      await rig.chat.delete('budget');
      await rig.chat.deleteWorkspace('q3');
      expect(rig.chat.deletedChat, isNull);
      // Nothing is left for the toast's Close to send.
      await rig.chat.flushDelete();
      await tester.pump(const Duration(minutes: 1));
      expect(llm.calls.where((c) => c.startsWith('deleteThread')), isEmpty);
      expect(rig.chat.problem, isNull);
      expect(rig.chat.threadsOf('q3'), isEmpty);
    });
  });
}
