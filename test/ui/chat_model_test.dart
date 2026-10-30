import 'dart:async';

import 'package:anywherellm/core/files.dart';
import 'package:anywherellm/ui/settings/rows.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

const _note = "The chat model is changed in AnythingLLM's web page.";

/// A server whose first workspace answers with a model of its own.
FakeAnythingLlm ownModel() => planningServer()
  ..spaces[0].settings.addAll({
    'chatProvider': 'ollama',
    'chatModel': 'llama3.1:8b',
  });

/// Every call that writes to the server's or a workspace's settings.
Iterable<String> writes(FakeAnythingLlm llm) => llm.calls.where(
  (c) => c.startsWith('updateWorkspace') || c.startsWith('updateSystem'),
);

/// Opens the open workspace's Answer from page, where the Chat model row is.
Future<Harness> openAnswerFrom(WidgetTester tester, FakeAnythingLlm llm) async {
  final h = await pumpApp(tester, llm: llm, size: const Size(390, 1200));
  h.shell
    ..showPane(Pane.files)
    ..showWorkspacePage(FilesSection.answers);
  await tester.pumpAndSettle();
  await h.files.openSection(FilesSection.answers);
  await tester.pumpAndSettle();
  return h;
}

void main() {
  group('the Answer from page', () {
    testWidgets('names a model of the workspace\'s own', (tester) async {
      await openAnswerFrom(tester, ownModel());
      expect(find.text('Chat model'), findsOneWidget);
      expect(find.text('llama3.1:8b'), findsOneWidget);
      expect(find.text(_note), findsOneWidget);
    });

    testWidgets('names a provider of its own that names no model', (
      tester,
    ) async {
      final llm = planningServer();
      llm.spaces[0].settings['chatProvider'] = 'openai';
      await openAnswerFrom(tester, llm);
      expect(find.text('OpenAI'), findsOneWidget);
    });

    testWidgets('names the system default once the settings are read', (
      tester,
    ) async {
      final llm = planningServer();
      final gate = llm.gates['systemSettings'] = Completer<void>();
      await openAnswerFrom(tester, llm);
      // The field below has System default as its hint, so the row is looked for in the card.
      expect(
        find.descendant(
          of: find.byType(InfoRow),
          matching: find.text('System default'),
        ),
        findsOneWidget,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('System default (qwen3:8b)'), findsOneWidget);
    });

    testWidgets('names the system\'s provider where it names no model', (
      tester,
    ) async {
      final llm = planningServer()
        ..system = const {'LLMProvider': 'anythingllm-router'};
      await openAnswerFrom(tester, llm);
      expect(find.text('System default (Model router)'), findsOneWidget);
    });

    testWidgets('the row opens nothing, and a save keeps the model', (
      tester,
    ) async {
      final llm = ownModel();
      final h = await openAnswerFrom(tester, llm);
      expect(control('Chat model, llama3.1:8b'), findsNothing);
      await tester.tap(find.text('Chat model'));
      await tester.pumpAndSettle();
      expect(writes(llm), isEmpty);
      expect(find.text('Save'), findsNothing);
      await tapVisible(tester, find.text('Files only'));
      await tester.pumpAndSettle();
      await tapVisible(tester, control('Save').last);
      await tester.pumpAndSettle();
      expect(writes(llm), ['updateWorkspace:q3']);
      expect(llm.spaces[0].settings['chatMode'], 'query');
      expect(llm.spaces[0].settings['chatProvider'], 'ollama');
      expect(llm.spaces[0].settings['chatModel'], 'llama3.1:8b');
      expect(h.sources.chatModel, 'llama3.1:8b');
    });

    testWidgets('settings that change the model are refused unsent', (
      tester,
    ) async {
      final llm = ownModel();
      final h = await openAnswerFrom(tester, llm);
      for (final draft in [
        '{"chatModel": "gpt-4o"}',
        '{"chatProvider": null, "chatModel": null}',
      ]) {
        expect(await h.files.save(draft), isFalse);
        expect(h.files.problems.single.text, contains('web page'));
      }
      expect(writes(llm), isEmpty);
      expect(llm.spaces[0].settings['chatModel'], 'llama3.1:8b');
    });
  });
}
