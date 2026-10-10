import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/ui/chat/composer.dart';
import 'package:anywherellm/ui/chat/model_picker.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

Finder inComposer(Finder finder) =>
    find.descendant(of: find.byType(Composer), matching: finder);

/// The chip, whatever model it names.
Finder get chip => find.byWidgetPredicate(
  (widget) => widget is Tappable && widget.label.startsWith('Chat model, '),
);

void main() {
  /// A server whose first workspace answers with a model of its own.
  FakeAnythingLlm ownModel() => planningServer()
    ..spaces[0].settings.addAll({
      'chatProvider': 'ollama',
      'chatModel': 'llama3.1:8b',
    });

  testWidgets('a workspace on the system model has no chip', (tester) async {
    await pumpApp(tester, llm: planningServer());
    await tester.pumpAndSettle();
    expect(chip, findsNothing);
    expect(inComposer(find.text('qwen3:8b')), findsNothing);
  });

  testWidgets('the chip names a model of its own', (tester) async {
    await pumpApp(tester, llm: ownModel());
    await tester.pumpAndSettle();
    expect(tester.widget<Tappable>(chip).label, 'Chat model, llama3.1:8b');
  });

  testWidgets('Save gives the workspace another provider and model', (
    tester,
  ) async {
    final llm = ownModel();
    final h = await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('Chat model for Q3 planning'), findsOneWidget);
    await tester.tap(find.text('Ollama'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenAI').last);
    await tester.pumpAndSettle();
    await tester.enterText(typingField(find.byType(ModelPicker)), 'gpt-4o');
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('updateWorkspace:q3'));
    expect(llm.spaces[0].settings['chatProvider'], 'openai');
    expect(llm.spaces[0].settings['chatModel'], 'gpt-4o');
    expect(h.sources.chatModel, 'gpt-4o');
    expect(find.text('Chat model for Q3 planning'), findsNothing);
    expect(inComposer(find.text('gpt-4o')), findsOneWidget);
  });

  testWidgets('Use system default clears both', (tester) async {
    final llm = planningServer();
    llm.spaces[0].settings
      ..['chatProvider'] = 'openai'
      ..['chatModel'] = 'gpt-4o';
    await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    expect(inComposer(find.text('gpt-4o')), findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(control('Use system default'));
    await tester.pumpAndSettle();
    expect(llm.spaces[0].settings['chatProvider'], isNull);
    expect(llm.spaces[0].settings['chatModel'], isNull);
    expect(chip, findsNothing);
  });

  testWidgets('a refusal keeps the picker open with why', (tester) async {
    final llm = ownModel();
    await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    llm.errors['updateWorkspace'] = const ApiException('The model is unknown.');
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Could not change the chat model'), findsOneWidget);
    expect(find.text('The model is unknown.'), findsOneWidget);
    expect(find.text('Chat model for Q3 planning'), findsOneWidget);
  });

  testWidgets('the chip is off while the workspace answers', (tester) async {
    final llm = ownModel()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    await h.chat.send('Go');
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<Tappable>(chip).onTap, isNull);
    await llm.chat!.close();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<Tappable>(chip).onTap, isNotNull);
  });
}
