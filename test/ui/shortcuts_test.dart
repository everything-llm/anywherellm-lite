import 'package:flutter/material.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('slash shortcut expands before sending and can be hidden', (
    tester,
  ) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm);
    h.chat.newChat();
    await tester.pumpAndSettle();

    await tester.enterText(composerField, '/translate');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('Translate'), findsOneWidget);

    await tester.enterText(composerField, 'French');
    await tester.pump();
    await tester.tap(control('Send'));
    await tester.pumpAndSettle();

    const expanded = 'Translate your last answer into French.';
    expect(llm.calls, contains('streamChat:th-1:$expanded'));
    expect(find.text(expanded), findsWidgets);

    await h.prefs.setSwitch(ChatSwitch.hideShortcutPrompts, true);
    await tester.pumpAndSettle();
    expect(find.text(expanded), findsOneWidget);
    expect(find.text('Translate'), findsOneWidget);
    expect(find.text('French'), findsOneWidget);
    expect(
      find.text('Shortcut · the server keeps the full prompt'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a shortcut pasted as /name into an empty message becomes a chip',
    (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      h.chat.newChat();
      await tester.pumpAndSettle();
      await tester.enterText(composerField, '/translate ');
      await tester.pump();
      expect(find.text('Translate'), findsOneWidget);
      expect(
        tester.widget<EditableText>(composerField).controller.text,
        isEmpty,
      );
    },
  );

  testWidgets('Edit puts a question back without the shortcut chosen before', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer());
    await tester.enterText(composerField, '/translate ');
    await tester.pump();
    expect(find.text('Translate'), findsOneWidget);
    await tester.longPress(find.text('What is the budget?'));
    await tester.pump();
    expect(find.text('Translate'), findsNothing);
    expect(
      tester.widget<EditableText>(composerField).controller.text,
      'What is the budget?',
    );
  });
}
