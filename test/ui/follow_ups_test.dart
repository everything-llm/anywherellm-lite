import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('the last answer of a chat has follow-ups under it', (
    tester,
  ) async {
    await pumpApp(tester, llm: answering('About 40k.'));
    expect(control('Make it shorter'), findsOneWidget);
    expect(control('Explain simply'), findsOneWidget);
    expect(control('Make a list'), findsOneWidget);
    expect(control('More shortcuts'), findsOneWidget);
  });

  testWidgets('a follow-up sends its shortcut as the next message', (
    tester,
  ) async {
    final llm = answering('About 40k.');
    final h = await pumpApp(tester, llm: llm);
    await tester.tap(control('Make it shorter'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      llm.calls,
      contains(
        'streamChat:budget:Say your last answer again in half the words.',
      ),
    );
    expect(h.chat.turns.first.shortcutUse, isNull);
    expect(
      h.chat.turns[h.chat.turns.length - 2].shortcutUse?.label,
      'Make it shorter',
    );
  });

  testWidgets('More puts a slash in the message to list the shortcuts', (
    tester,
  ) async {
    await pumpApp(tester, llm: answering('About 40k.'));
    await tester.ensureVisible(control('More shortcuts'));
    await tester.pump();
    await tester.tap(control('More shortcuts'));
    await tester.pump();
    expect(tester.widget<EditableText>(composerField).controller.text, '/');
  });

  testWidgets('a new chat has no follow-ups', (tester) async {
    final h = await pumpApp(tester, llm: answering('About 40k.'));
    h.chat.newChat();
    await tester.pump(const Duration(milliseconds: 500));
    expect(control('Make it shorter'), findsNothing);
  });
}
