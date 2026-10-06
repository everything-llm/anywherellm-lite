import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/ui/files/system_form.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/widgets/fields.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

const _secret = 'sk-live-0123456789';

/// A control on the settings page, by the label a screen reader hears.
Finder control(String label) => find.descendant(
  of: find.byType(SystemPage),
  matching: find.byWidgetPredicate(
    (widget) => widget is Tappable && widget.label == label,
  ),
);

/// The page's field for setting [key].
Finder field(String key) => find.descendant(
  of: find.byType(SystemPage),
  matching: find.byWidgetPredicate((w) => w is AppField && w.label == key),
);

FakeAnythingLlm server() => planningServer()
  ..system = {
    'LLMProvider': 'ollama',
    'OllamaLLMModelPref': 'qwen3:8b',
    'OllamaLLMAuthToken': true,
    'EmbeddingEngine': 'native',
    'EmbeddingModelPref': 'Xenova/all-MiniLM-L6-v2',
    'VectorDB': 'lancedb',
  };

Future<Harness> openSystem(WidgetTester tester, FakeAnythingLlm llm) async {
  final h = await pumpApp(tester, llm: llm, size: const Size(1400, 2400));
  h.shell.showPane(Pane.files);
  await tester.pumpAndSettle();
  h.files.select('/settings/system.json');
  await tester.pumpAndSettle();
  return h;
}

Future<void> type(WidgetTester tester, String key, String text) async {
  await tester.enterText(
    find.descendant(of: field(key), matching: find.byType(EditableText)),
    text,
  );
  await tester.pump();
}

void main() {
  testWidgets('the form shows each setting, and a set secret only as set', (
    tester,
  ) async {
    final llm = server()
      ..system = {...server().system, 'OllamaLLMAuthToken': true};
    await openSystem(tester, llm);
    expect(find.text('qwen3:8b'), findsOneWidget);
    expect(find.text('lancedb'), findsOneWidget);
    expect(find.text('Set. Type a new one to replace it.'), findsOneWidget);
    expect(find.textContaining(_secret), findsNothing);
  });

  testWidgets('a changed model is saved, and the settings are read again', (
    tester,
  ) async {
    final llm = server();
    await openSystem(tester, llm);
    await type(tester, 'OllamaLLMModelPref', 'qwen3:14b');
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('updateSystem:OllamaLLMModelPref'));
    expect(llm.system['OllamaLLMModelPref'], 'qwen3:14b');
    expect(find.text('qwen3:14b'), findsOneWidget);
  });

  testWidgets('a replaced secret is sent, and never shown after', (
    tester,
  ) async {
    final llm = server();
    await openSystem(tester, llm);
    await type(tester, 'OllamaLLMAuthToken', _secret);
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('updateSystem:OllamaLLMAuthToken'));
    expect(find.textContaining(_secret), findsNothing);
  });

  testWidgets(
    'changing the embedder asks first, naming the vectors it deletes',
    (tester) async {
      final llm = server();
      final h = await openSystem(tester, llm);
      await h.system.readVectors();
      await type(tester, 'EmbeddingModelPref', 'nomic-embed-text');
      await tester.tap(control('Save'));
      await tester.pumpAndSettle();
      expect(llm.calls.where((c) => c.startsWith('updateSystem')), isEmpty);
      expect(
        find.textContaining('makes the server delete all 796 vectors'),
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
    },
  );

  testWidgets('a refused save says why, and shows what the server now has', (
    tester,
  ) async {
    final llm = server()
      ..errors['updateSystem'] = const ApiException('Invalid model');
    await openSystem(tester, llm);
    await type(tester, 'OllamaLLMModelPref', 'nope');
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save the settings'), findsOneWidget);
    expect(find.text('Invalid model'), findsOneWidget);
    expect(
      llm.calls.where((c) => c == 'systemSettings').length,
      greaterThan(1),
    );
  });

  testWidgets(
    'Edit as JSON shows no secret, and saves through the same check',
    (tester) async {
      final llm = server();
      final h = await openSystem(tester, llm);
      await tester.tap(control('Edit as JSON'));
      await tester.pumpAndSettle();
      final editor = find.descendant(
        of: find.byType(SystemPage),
        matching: find.byType(EditableText),
      );
      final text = tester.widget<EditableText>(editor).controller.text;
      expect(text, contains('"OllamaLLMModelPref": "qwen3:8b"'));
      expect(text, isNot(contains('OllamaLLMAuthToken')));
      await tester.enterText(editor, '{"VectorDB": "pgvector"}');
      await tester.pump();
      await tester.tap(control('Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('switching it deletes every vector'),
        findsOneWidget,
      );
      expect(llm.calls.where((c) => c.startsWith('updateSystem')), isEmpty);
      expect(h.system.settingsAsJson, isTrue);
    },
  );
}
