import 'package:anywherellm/core/commands.dart';
import 'package:anywherellm/ui/chat/slash_menu.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

const _research = SlashCommand(
  command: '/deep-research',
  prompt: '@agent Research:',
  description: 'Research a question in depth',
);

Finder get _composer => typingField();

String _draft(WidgetTester tester) =>
    tester.widget<EditableText>(_composer.last).controller.text;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_composer.last, text);
  await tester.pump();
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

void main() {
  testWidgets('a slash lists the commands, and typing narrows them', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer()..presets = const [_research]);
    await _type(tester, '/');
    expect(find.byType(SlashMenu), findsOneWidget);
    expect(find.text('/reset'), findsOneWidget);
    expect(find.text('Research a question in depth'), findsOneWidget);

    await _type(tester, '/de');
    expect(find.text('/reset'), findsNothing);
    expect(find.text('/deep-research'), findsOneWidget);

    await _type(tester, '/deep-research tides');
    expect(find.byType(SlashMenu), findsNothing);
  });

  testWidgets('arrows move, Enter fills the command, Enter again sends', (
    tester,
  ) async {
    final llm = planningServer()..presets = const [_research];
    await pumpApp(tester, llm: llm);
    await _type(tester, '/');
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.enter);
    expect(_draft(tester), '/deep-research ');
    expect(find.byType(SlashMenu), findsNothing);
    expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);

    await _type(tester, '/reset');
    await _key(tester, LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(llm.calls, contains('resetChat:budget'));
    expect(find.text('About 40k.'), findsNothing);
  });

  testWidgets('Esc closes the menu until the message changes', (tester) async {
    await pumpApp(tester, llm: planningServer());
    await _type(tester, '/re');
    await _key(tester, LogicalKeyboardKey.escape);
    expect(find.byType(SlashMenu), findsNothing);
    await _type(tester, '/r');
    expect(find.byType(SlashMenu), findsOneWidget);
  });

  testWidgets('the slash button starts a command in an empty message', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer());
    await tester.tap(
      find.byWidgetPredicate((w) => w is Tappable && w.label == 'Commands'),
    );
    await tester.pump();
    expect(_draft(tester), '/');
    expect(find.byType(SlashMenu), findsOneWidget);
  });
}
