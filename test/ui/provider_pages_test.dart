import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/ui/settings/settings_dialog.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/widgets/fields.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

const _secret = 'sk-live-0123456789';

/// A control in Settings, by the label a screen reader hears.
Finder control(String label) => find.descendant(
  of: find.byType(SettingsDialog),
  matching: find.byWidgetPredicate(
    (widget) => widget is Tappable && widget.label == label,
  ),
);

/// The text of the field labelled [label].
Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is AppField && w.label == label),
  matching: find.byType(EditableText),
);

String text(WidgetTester tester, String label) =>
    tester.widget<EditableText>(field(label)).controller.text;

FakeAnythingLlm server() => planningServer()
  ..system = {
    'LLMProvider': 'ollama',
    'OllamaLLMModelPref': 'qwen3:8b',
    'OllamaLLMBasePath': 'http://127.0.0.1:11434',
    'OllamaLLMAuthToken': true,
    'AnthropicModelPref': 'claude',
    'EmbeddingEngine': 'native',
    'EmbeddingModelPref': 'Xenova/all-MiniLM-L6-v2',
    'VectorDB': 'lancedb',
  };

Future<Harness> openPage(
  WidgetTester tester,
  FakeAnythingLlm llm,
  SettingsPage page,
) async {
  final h = await pumpApp(tester, llm: llm, size: const Size(1400, 2400));
  h.shell.openSettings(page);
  await tester.pumpAndSettle();
  return h;
}

Future<void> pick(WidgetTester tester, String choice, {int which = 0}) async {
  await tester.tap(find.byType(DropdownButton<String>).at(which));
  await tester.pumpAndSettle();
  await tester.tap(find.text(choice).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the chat model shows the provider by name and its settings', (
    tester,
  ) async {
    await openPage(tester, server(), SettingsPage.chatModel);
    expect(find.text('Ollama'), findsOneWidget);
    expect(text(tester, 'Model'), 'qwen3:8b');
    expect(text(tester, 'Base URL'), 'http://127.0.0.1:11434');
    expect(find.text('Set, not shown'), findsOneWidget);
  });

  testWidgets('a changed model is saved alone, and read again', (tester) async {
    final llm = server();
    await openPage(tester, llm, SettingsPage.chatModel);
    await tester.enterText(field('Model'), 'qwen3:14b');
    await tester.pump();
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('updateSystem:OllamaLLMModelPref'));
    expect(llm.system['OllamaLLMModelPref'], 'qwen3:14b');
    expect(text(tester, 'Model'), 'qwen3:14b');
  });

  testWidgets('another provider shows its own settings, and saves them', (
    tester,
  ) async {
    final llm = server();
    await openPage(tester, llm, SettingsPage.chatModel);
    await pick(tester, 'Anthropic');
    expect(text(tester, 'Model'), 'claude');
    expect(field('Base URL'), findsNothing);
    await tester.enterText(field('Model'), 'claude-sonnet-5-5');
    await tester.enterText(field('API key'), _secret);
    await tester.pump();
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    expect(llm.system['LLMProvider'], 'anthropic');
    expect(llm.system['AnthropicModelPref'], 'claude-sonnet-5-5');
    expect(llm.system['AnthropicApiKey'], _secret);
    expect(llm.system['OllamaLLMModelPref'], 'qwen3:8b');
  });

  testWidgets('a set secret is replaced only on asking, and never shown', (
    tester,
  ) async {
    final llm = server();
    await openPage(tester, llm, SettingsPage.chatModel);
    expect(field('Auth token'), findsNothing);
    await tester.tap(control('Replace'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Auth token'), _secret);
    await tester.pump();
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('updateSystem:OllamaLLMAuthToken'));
    expect(find.textContaining(_secret), findsNothing);
    expect(find.text('Set, not shown'), findsOneWidget);
  });

  testWidgets('Revert puts back what the server has, and sends nothing', (
    tester,
  ) async {
    final llm = server();
    await openPage(tester, llm, SettingsPage.chatModel);
    await pick(tester, 'Oobabooga Web UI');
    expect(field('Model'), findsNothing);
    await tester.tap(control('Revert'));
    await tester.pumpAndSettle();
    expect(text(tester, 'Model'), 'qwen3:8b');
    expect(llm.calls.where((c) => c.startsWith('updateSystem')), isEmpty);
  });

  testWidgets('a refused save says why, and shows what the server has', (
    tester,
  ) async {
    final llm = server()
      ..errors['updateSystem'] = const ApiException('Invalid model');
    await openPage(tester, llm, SettingsPage.chatModel);
    await tester.enterText(field('Model'), 'nope');
    await tester.pump();
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save the settings'), findsOneWidget);
    expect(find.text('Invalid model'), findsOneWidget);
    expect(text(tester, 'Model'), 'qwen3:8b');
  });

  testWidgets('changing the search model asks first, naming the passages', (
    tester,
  ) async {
    final llm = server();
    final h = await openPage(tester, llm, SettingsPage.searchModel);
    expect(h.system.vectors, isNull);
    await tester.enterText(field('Model'), 'nomic-embed-text');
    await tester.pump();
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    expect(llm.calls.where((c) => c.startsWith('updateSystem')), isEmpty);
    expect(
      find.textContaining('makes the server delete all 796 passages'),
      findsOneWidget,
    );
    await tester.tap(control('Cancel'));
    await tester.pumpAndSettle();
    expect(llm.calls.where((c) => c.startsWith('updateSystem')), isEmpty);
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    await tester.tap(control('Change and delete'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('updateSystem:EmbeddingModelPref'));
    expect(h.system.vectors, isNull, reason: 'the count went with the reset');
  });

  testWidgets('storage shows the database and its passages, never a picker', (
    tester,
  ) async {
    final llm = server();
    await openPage(tester, llm, SettingsPage.storage);
    expect(find.text('LanceDB'), findsOneWidget);
    expect(find.text('796 passages'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(control('Save'), findsNothing);
  });

  testWidgets('voice saves both choosers together', (tester) async {
    final llm = server()
      ..system = {
        ...server().system,
        'TextToSpeechProvider': 'native',
        'SpeechToTextProvider': 'native',
      };
    await openPage(tester, llm, SettingsPage.voice);
    await pick(tester, 'OpenAI');
    await tester.enterText(field('Voice'), 'nova');
    await tester.pump();
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    expect(llm.system['TextToSpeechProvider'], 'openai');
    expect(llm.system['TTSOpenAIVoiceModel'], 'nova');
    expect(llm.system['SpeechToTextProvider'], 'native');
  });

  testWidgets('the JSON page shows no secret, and refuses the database', (
    tester,
  ) async {
    final llm = server();
    await openPage(tester, llm, SettingsPage.json);
    final editor = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'system.json',
      ),
      matching: find.byType(EditableText),
    );
    final json = tester.widget<EditableText>(editor).controller.text;
    expect(json, contains('"OllamaLLMModelPref": "qwen3:8b"'));
    expect(json, isNot(contains('OllamaLLMAuthToken')));
    await tester.enterText(editor, '{"VectorDB": "pgvector"}');
    await tester.pump();
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('switching it deletes every vector'),
      findsOneWidget,
    );
    expect(llm.calls.where((c) => c.startsWith('updateSystem')), isEmpty);
  });

  testWidgets('privacy names the providers and switches telemetry', (
    tester,
  ) async {
    final llm = server();
    await openPage(tester, llm, SettingsPage.privacy);
    expect(find.text('Ollama, qwen3:8b'), findsOneWidget);
    expect(find.text('AnythingLLM Embedder'), findsOneWidget);
    await tester.tap(control('Anonymous telemetry'));
    await tester.pumpAndSettle();
    expect(llm.system['DisableTelemetry'], 'true');
  });
}
