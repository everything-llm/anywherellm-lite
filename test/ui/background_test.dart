import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/core/notes.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/state/chat_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_background.dart';
import '../support/pump.dart';

const _dropped = CutOff(
  'The connection dropped: Connection closed while receiving data',
);

/// The app with a question sent and its answer held open, so a test drops or ends it.
Future<(Harness, FakeAnythingLlm)> _asking(
  WidgetTester tester, {
  FakeBackground? background,
}) async {
  final llm = planningServer()..hold = true;
  final h = await pumpApp(tester, llm: llm, background: background);
  await h.chat.send('Can you build it in English?');
  await tester.pump();
  return (h, llm);
}

/// The server saves the answer to [thread] after the connection dropped, as an agent does.
void _saved(FakeAnythingLlm llm, String thread, String text) {
  llm.histories[thread] = [
    ...?llm.histories[thread],
    const ChatMessage(
      role: Role.user,
      text: 'Can you build it in English?',
      chatId: 100,
    ),
    ChatMessage(role: Role.assistant, text: text, chatId: 100),
  ];
}

void main() {
  group('a dropped answer', () {
    testWidgets('waits for the server instead of failing', (tester) async {
      final (h, llm) = await _asking(tester);
      llm.chat!
        ..add(const TextChunk('Building it'))
        ..addError(_dropped);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Still answering on the server'), findsOneWidget);
      expect(find.text('Ask again'), findsNothing);
      expect(h.chat.canRetry, isFalse);
      expect(h.chat.working, isTrue);

      _saved(llm, h.chat.activeThread!, 'Here is the English word game.');
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('Still answering on the server'), findsNothing);
      expect(find.text('Here is the English word game.'), findsOneWidget);
      expect(h.chat.working, isFalse);
      expect(h.chat.finished?.text, 'Here is the English word game.');
    });

    testWidgets('Check now reads the chat at once', (tester) async {
      final (h, llm) = await _asking(tester);
      llm.chat!.addError(_dropped);
      await tester.pump(const Duration(milliseconds: 300));
      _saved(llm, h.chat.activeThread!, 'Saved meanwhile.');
      await tester.tap(find.text('Check now'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Saved meanwhile.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('fails once the server saved nothing for 30 minutes', (
      tester,
    ) async {
      final (h, llm) = await _asking(tester);
      llm.chat!.addError(_dropped);
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < ChatController.waitReads; i++) {
        await tester.pump(const Duration(seconds: 20));
      }
      await tester.pump();
      expect(find.text('Still answering on the server'), findsNothing);
      expect(
        find.text(
          'The connection dropped, and the server saved no answer within 30 minutes.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ask again'), findsOneWidget);
      expect(h.chat.working, isFalse);
    });

    testWidgets('a real failure still fails at once', (tester) async {
      final (h, llm) = await _asking(tester);
      llm.chat!.addError(const ApiException('The server stopped the answer.'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Still answering on the server'), findsNothing);
      expect(find.text('Ask again'), findsOneWidget);
      expect(h.chat.working, isFalse);
    });
  });

  group('the app out of sight', () {
    testWidgets('holds itself while an answer runs or is waited for', (
      tester,
    ) async {
      final background = FakeBackground();
      final (h, llm) = await _asking(tester, background: background);
      expect(background.held, ['Answering in Q3 planning']);

      llm.chat!.addError(_dropped);
      await tester.pump(const Duration(milliseconds: 300));
      // Still held: the answer is waited for.
      expect(background.held, ['Answering in Q3 planning']);

      _saved(llm, h.chat.activeThread!, 'Done.');
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(background.held, ['Answering in Q3 planning', null]);
    });

    testWidgets('says an answer is ready only while out of sight', (
      tester,
    ) async {
      final background = FakeBackground();
      final (h, llm) = await _asking(tester, background: background);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      llm.chat!
        ..add(const WholeAnswer('Here is the game.'))
        ..add(const ChatDone([]));
      await llm.chat!.close();
      await tester.pump();
      expect(background.readied, [
        '${h.chat.threadsOf(h.chat.activeSlug!).firstWhere((t) => t.slug == h.chat.activeThread).name}: '
            'Here is the game. @ ${h.chat.activeSlug}/${h.chat.activeThread}',
      ]);
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }

      await h.chat.send('And in Swedish?');
      await tester.pump();
      llm.chat!.add(const ChatDone([]));
      await llm.chat!.close();
      await tester.pump();
      expect(background.readied, hasLength(1));
    });

    testWidgets('Back on the first screen puts the app aside, not away', (
      tester,
    ) async {
      final background = FakeBackground();
      await pumpApp(tester, background: background, onChat: false);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(background.left, 1);
    });

    testWidgets('a ready answer tapped opens its chat', (tester) async {
      final background = FakeBackground();
      final h = await pumpApp(
        tester,
        llm: planningServer(),
        background: background,
        onChat: false,
      );
      final slug = h.chat.workspaces.first.slug;
      final thread = h.chat.threadsOf(slug).first.slug;
      background.tap(ChatTarget(slug, thread));
      await tester.pumpAndSettle();
      expect(h.shell.chatOpen, isTrue);
      expect((h.chat.activeSlug, h.chat.activeThread), (slug, thread));
    });
  });
}
