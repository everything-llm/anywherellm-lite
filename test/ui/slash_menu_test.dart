import 'package:anywherellm/core/commands.dart';
import 'package:anywherellm/ui/chat/slash_menu.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

const _research = SlashCommand(
  command: '/deep-research',
  prompt: '@agent Research:',
  description: 'Research a question in depth',
);

Finder get _composer => composerField;

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
    expect(find.byType(SlashStrip), findsOneWidget);
    expect(find.text('/reset'), findsOneWidget);
    expect(find.text('/deep-research'), findsOneWidget);

    await _type(tester, '/de');
    expect(find.text('/reset'), findsNothing);
    expect(find.text('/deep-research'), findsOneWidget);

    await _type(tester, '/deep-research tides');
    expect(find.byType(SlashStrip), findsNothing);
  });

  testWidgets('Enter fills the first command, and Enter again sends', (
    tester,
  ) async {
    final llm = planningServer()..presets = const [_research];
    await pumpApp(tester, llm: llm);
    await _type(tester, '/de');
    await _key(tester, LogicalKeyboardKey.enter);
    expect(_draft(tester), '/deep-research ');
    expect(find.byType(SlashStrip), findsNothing);
    expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);

    await _type(tester, '/reset');
    await _key(tester, LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(llm.calls, contains('resetChat:budget'));
    expect(find.text('About 40k.'), findsNothing);
  });

  testWidgets(
    'there is no Commands button; typing / opens them over the composer',
    (tester) async {
      await pumpApp(tester, llm: planningServer());
      expect(
        find.byWidgetPredicate((w) => w is Tappable && w.label == 'Commands'),
        findsNothing,
      );
      await tester.enterText(composerField, '/');
      await tester.pump();
      expect(find.byType(SlashStrip), findsOneWidget);
      // The commands are a card of their own, above the composer's card.
      expect(
        tester.getRect(find.byType(SlashStrip)).bottom,
        lessThan(tester.getRect(composerField).top),
      );
    },
  );

  testWidgets(
    'the commands are suggestions that leave the field and its focus alone',
    (tester) async {
      await pumpApp(tester, llm: planningServer()..presets = const [_research]);
      await tester.showKeyboard(composerField);
      final field = tester.state(composerField);
      await _type(tester, '/');
      expect(find.byType(SlashStrip), findsOneWidget);
      // The field is the same one, so the keyboard stays as it was.
      expect(identical(tester.state(composerField), field), isTrue);
      expect(
        tester.widget<EditableText>(composerField).focusNode.hasFocus,
        isTrue,
      );
      // One line of suggestions, not a card of them.
      expect(tester.getSize(find.byType(SlashStrip)).height, lessThan(80));
      await tester.tap(control('/deep-research: Research a question in depth'));
      await tester.pump();
      expect(_draft(tester), '/deep-research ');
      expect(find.byType(SlashStrip), findsNothing);
      expect(identical(tester.state(composerField), field), isTrue);
      expect(
        tester.widget<EditableText>(composerField).focusNode.hasFocus,
        isTrue,
      );
    },
  );
}
