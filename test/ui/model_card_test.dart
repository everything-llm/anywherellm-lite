import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/ui/settings/model_card.dart';
import 'package:anywherellm/ui/widgets/fields.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// A control in the card, by the label a screen reader hears.
Finder control(String label) => find.descendant(
  of: find.byType(ModelCard),
  matching: find.byWidgetPredicate(
    (widget) => widget is Tappable && widget.label == label,
  ),
);

Finder modelField() => find.descendant(
  of: find.byWidgetPredicate((w) => w is AppField && w.label == 'Model'),
  matching: find.byType(EditableText),
);

String modelText(WidgetTester tester) =>
    tester.widget<EditableText>(modelField()).controller.text;

Future<Harness> openSettings(WidgetTester tester, FakeAnythingLlm llm) async {
  final h = await pumpApp(tester, llm: llm, size: const Size(1400, 2400));
  h.shell.openSettings();
  await tester.pumpAndSettle();
  return h;
}

Future<void> pickProvider(WidgetTester tester, String provider) async {
  await tester.tap(find.byType(DropdownButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(provider).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Settings shows the server\'s provider and model', (
    tester,
  ) async {
    await openSettings(tester, planningServer());
    expect(find.byType(ModelCard), findsOneWidget);
    expect(find.text('ollama'), findsOneWidget);
    expect(modelText(tester), 'qwen3:8b');
  });

  testWidgets('a changed model is saved, and the settings are read again', (
    tester,
  ) async {
    final llm = planningServer();
    await openSettings(tester, llm);
    await tester.enterText(modelField(), 'qwen3:14b');
    await tester.pump();
    await tester.tap(control('Save model'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('updateSystem:OllamaLLMModelPref'));
    expect(llm.system['OllamaLLMModelPref'], 'qwen3:14b');
    expect(modelText(tester), 'qwen3:14b');
  });

  testWidgets('another provider shows its own model, and saves both', (
    tester,
  ) async {
    final llm = planningServer()
      ..system = {...planningServer().system, 'AnthropicModelPref': 'claude'};
    await openSettings(tester, llm);
    await pickProvider(tester, 'anthropic');
    expect(modelText(tester), 'claude');
    await tester.enterText(modelField(), 'claude-sonnet-5-5');
    await tester.pump();
    await tester.tap(control('Save model'));
    await tester.pumpAndSettle();
    expect(llm.system['LLMProvider'], 'anthropic');
    expect(llm.system['AnthropicModelPref'], 'claude-sonnet-5-5');
    expect(llm.system['OllamaLLMModelPref'], 'qwen3:8b');
  });

  testWidgets('Revert puts back the provider and model the server has', (
    tester,
  ) async {
    final llm = planningServer();
    await openSettings(tester, llm);
    await pickProvider(tester, 'textgenwebui');
    expect(modelField(), findsNothing);
    expect(find.text('This provider picks its own model.'), findsOneWidget);
    await tester.tap(control('Revert'));
    await tester.pumpAndSettle();
    expect(modelText(tester), 'qwen3:8b');
    expect(llm.calls.where((c) => c.startsWith('updateSystem')), isEmpty);
  });

  testWidgets('a refused save says why', (tester) async {
    final llm = planningServer()
      ..errors['updateSystem'] = const ApiException('Invalid model');
    await openSettings(tester, llm);
    await tester.enterText(modelField(), 'qwen3:14b');
    await tester.pump();
    await tester.tap(control('Save model'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save the settings'), findsOneWidget);
    expect(modelText(tester), 'qwen3:8b');
  });

  testWidgets('with no server there is no model card', (tester) async {
    final h = await pumpApp(tester, llm: planningServer(), connection: null);
    h.shell.openSettings();
    await tester.pumpAndSettle();
    expect(find.byType(ModelCard), findsNothing);
  });
}
