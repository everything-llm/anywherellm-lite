import 'dart:async';

import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/core/files.dart';
import 'package:anywherellm/ui/chat/model_picker.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// A server whose first workspace answers with a model of its own.
FakeAnythingLlm ownModel() => planningServer()
  ..spaces[0].settings.addAll({
    'chatProvider': 'ollama',
    'chatModel': 'llama3.1:8b',
  });

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

/// Opens the picker from the Chat model row.
Future<void> openPicker(WidgetTester tester) async {
  await tapVisible(tester, find.text('Chat model'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the row names a model of the workspace\'s own', (tester) async {
    await openAnswerFrom(tester, ownModel());
    expect(find.text('llama3.1:8b'), findsOneWidget);
  });

  testWidgets('names the system\'s model once the settings are read', (
    tester,
  ) async {
    final llm = planningServer();
    final gate = llm.gates['systemSettings'] = Completer<void>();
    await openAnswerFrom(tester, llm);
    await openPicker(tester);
    expect(find.text('Empty uses the system default.'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(
      find.text('Empty uses the system default, qwen3:8b.'),
      findsOneWidget,
    );
    expect(find.text('System default (Ollama)'), findsOneWidget);
  });

  testWidgets('Save gives the workspace another provider and model', (
    tester,
  ) async {
    final llm = ownModel();
    final h = await openAnswerFrom(tester, llm);
    await openPicker(tester);
    expect(find.text('Chat model for Q3 planning'), findsOneWidget);
    await tester.tap(find.text('Ollama'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI').last);
    await tester.pumpAndSettle();
    await tester.enterText(typingField(find.byType(ModelPicker)), 'gpt-4o');
    await tapVisible(tester, control('Save').last);
    await tester.pumpAndSettle();
    expect(llm.calls, contains('updateWorkspace:q3'));
    expect(llm.spaces[0].settings['chatProvider'], 'openai');
    expect(llm.spaces[0].settings['chatModel'], 'gpt-4o');
    expect(h.sources.chatModel, 'gpt-4o');
    expect(find.text('Chat model for Q3 planning'), findsNothing);
  });

  testWidgets('Use system default clears both', (tester) async {
    final llm = planningServer();
    llm.spaces[0].settings
      ..['chatProvider'] = 'openai'
      ..['chatModel'] = 'gpt-4o';
    final h = await openAnswerFrom(tester, llm);
    await openPicker(tester);
    await tapVisible(tester, control('Use system default'));
    await tester.pumpAndSettle();
    expect(llm.spaces[0].settings['chatProvider'], isNull);
    expect(llm.spaces[0].settings['chatModel'], isNull);
    expect(h.sources.chatModel, isNull);
  });

  testWidgets('a refusal keeps the picker open with why', (tester) async {
    final llm = ownModel();
    await openAnswerFrom(tester, llm);
    await openPicker(tester);
    llm.errors['updateWorkspace'] = const ApiException('The model is unknown.');
    await tapVisible(tester, control('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('Could not change the chat model'), findsOneWidget);
    expect(find.text('The model is unknown.'), findsOneWidget);
    expect(find.text('Chat model for Q3 planning'), findsOneWidget);
  });
}
