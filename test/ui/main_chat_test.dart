import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/state/chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
import '../support/rig.dart';

/// Q3 planning's Main chat.
final _main = mainChatOf('q3');

/// [planningServer] with one exchange in Q3 planning's Main chat, asked on the web page.
FakeAnythingLlm _withMainChat() =>
    planningServer()..saveExchange(_main, 'Who owns the launch?', 'Dana does.');

Future<Rig> _started(FakeAnythingLlm llm, {Prefs prefs = const Prefs()}) async {
  final rig = Rig(
    llm: llm,
    connection: sampleConnection,
    prefsStore: FakePrefsStore(prefs),
  );
  addTearDown(rig.dispose);
  await rig.start();
  return rig;
}

/// [rig] on Q3 planning's Main chat, read.
Future<ChatController> _onMain(Rig rig) async {
  await rig.chat.open(_main);
  return rig.chat;
}

void main() {
  group('Main chat', () {
    test('opens on the workspace\'s own chats, as no thread', () async {
      final llm = _withMainChat();
      final chat = await _onMain(await _started(llm));
      expect(llm.calls, contains('history:$_main'));
      expect(chat.activeThread, _main);
      expect(chat.onMainChat, isTrue);
      expect(chat.thread, isNull);
      expect(chat.title, mainChatName);
      expect(chat.turns.map((t) => t.text), [
        'Who owns the launch?',
        'Dana does.',
      ]);
      expect(chat.threadsOf('q3').map((t) => t.slug), ['priorities', 'budget']);
    });

    test('is asked in place, with no thread made and no name given', () async {
      final llm = _withMainChat();
      final chat = await _onMain(await _started(llm));
      await chat.send('And the budget?');
      await pumpEventQueue();
      expect(llm.calls, contains('streamChat:$_main:And the budget?'));
      expect(llm.calls.where((c) => c.startsWith('createThread')), isEmpty);
      expect(llm.calls.where((c) => c.startsWith('renameThread')), isEmpty);
      expect(chat.activeThread, _main);
      expect(chat.title, mainChatName);
      expect(chat.turns.map((t) => t.text), [
        'Who owns the launch?',
        'Dana does.',
        'And the budget?',
        'Here is what your sources say.',
      ]);
      expect(chat.threadsOf('q3'), hasLength(2));
    });

    test('clears with reset, on the workspace itself', () async {
      final llm = _withMainChat();
      final chat = await _onMain(await _started(llm));
      expect(chat.canReset, isTrue);
      await chat.reset();
      expect(llm.calls, contains('resetChat:$_main'));
      expect(chat.turns, isEmpty);
      expect(llm.histories[_main], isNull);
    });

    test('asks its last question again with Retry', () async {
      final llm = _withMainChat();
      final chat = await _onMain(await _started(llm));
      expect(chat.canRetry, isTrue);
      await chat.retry();
      await pumpEventQueue();
      expect(llm.calls, contains('streamChat:$_main:Who owns the launch?'));
      expect(chat.turns.last.text, 'Here is what your sources say.');
    });

    test('sends a waiting message once the answer before it ends', () async {
      final llm = _withMainChat()..hold = true;
      final chat = await _onMain(await _started(llm));
      await chat.send('First?');
      await pumpEventQueue();
      expect(chat.sendWhenDone('Second?'), isTrue);
      expect(chat.onDeck.map((o) => o.text), ['Second?']);
      llm.chats[_main]!.add(const ChatDone([]));
      await llm.chats[_main]!.close();
      await pumpEventQueue();
      expect(llm.calls, contains('streamChat:$_main:Second?'));
      expect(chat.onDeck, isEmpty);
    });

    test('is ready once its answer ends while another chat shows', () async {
      final llm = _withMainChat()..hold = true;
      final chat = await _onMain(await _started(llm));
      await chat.send('And the budget?');
      await pumpEventQueue();
      await chat.open('budget');
      llm.chats[_main]!.add(const ChatDone([]));
      await llm.chats[_main]!.close();
      await pumpEventQueue();
      expect(chat.isReady(_main), isTrue);
      expect(chat.nameOf('q3', _main), mainChatName);
      await chat.open(_main);
      expect(chat.isReady(_main), isFalse);
    });

    test('can be neither renamed nor deleted', () async {
      final llm = _withMainChat();
      final chat = await _onMain(await _started(llm));
      await chat.rename(_main, 'Launch');
      await chat.delete(_main);
      expect(llm.calls.where((c) => c.startsWith('renameThread')), isEmpty);
      expect(chat.deletedChat, isNull);
      expect(chat.activeThread, _main);
      expect(chat.title, mainChatName);
    });

    test('gives way to a draft on New chat, even when empty', () async {
      final llm = planningServer();
      final chat = await _onMain(await _started(llm));
      expect(chat.turns, isEmpty);
      chat.newChat();
      expect(chat.activeThread, isNull);
      expect(chat.title, newChatName);
    });

    test('stays on screen when the chats are read again', () async {
      final llm = _withMainChat();
      final chat = await _onMain(await _started(llm));
      llm.saveExchange(_main, 'And now?', 'Still Dana.', chatId: 101);
      await chat.refresh();
      expect(chat.activeThread, _main);
      expect(chat.turns.last.text, 'Still Dana.');
    });

    test(
      'opens at start when it was the last on screen, and is never Recent',
      () async {
        final llm = _withMainChat();
        final rig = await _started(llm);
        await _onMain(rig);
        await pumpEventQueue();
        expect(rig.prefs.prefs.lastChat?.thread, _main);
        expect(rig.prefs.recentIn('q3'), isNot(contains(_main)));

        final again = await _started(llm, prefs: rig.prefs.prefs);
        expect(again.chat.activeThread, _main);
        expect(again.chat.turns.last.text, 'Dana does.');
      },
    );

    test('is each workspace\'s own', () async {
      final llm = _withMainChat();
      final chat = await _onMain(await _started(llm));
      await chat.select('household', thread: mainChatOf('household'));
      expect(llm.calls, contains('history:${mainChatOf('household')}'));
      expect(chat.title, mainChatName);
      expect(chat.turns, isEmpty);
      await chat.select('q3', thread: _main);
      expect(chat.turns.last.text, 'Dana does.');
    });
  });
}
