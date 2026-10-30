import 'package:flutter/material.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/shortcuts.dart';
import 'package:anywherellm/ui/chat/composer.dart';
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

  testWidgets('a message waiting follows Hide shortcut prompts too', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer()..hold = true);
    await h.chat.send('And next quarter?');
    const expanded = 'Translate your last answer into French.';
    expect(
      h.chat.sendWhenDone(
        expanded,
        shortcutUse: const ShortcutUse(label: 'Translate', detail: 'French'),
      ),
      isTrue,
    );
    await tester.pump();
    expect(find.text(expanded), findsOneWidget);
    await h.prefs.setSwitch(ChatSwitch.hideShortcutPrompts, true);
    await tester.pump();
    expect(find.text(expanded), findsNothing);
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

  testWidgets('Summarise is /summarise, and /summarize still finds it', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer());
    h.chat.newChat();
    await tester.pumpAndSettle();
    await tester.enterText(composerField, '/summariz');
    await tester.pump();
    expect(find.text('/summarise'), findsOneWidget);
    await tester.enterText(composerField, '/summarize ');
    await tester.pump();
    expect(find.text('Summarise'), findsOneWidget);
    expect(tester.widget<EditableText>(composerField).controller.text, isEmpty);
    expect(h.prefs.shortcutNameAvailable('summarize'), isFalse);
    expect(h.prefs.shortcutNameAvailable('summarise'), isFalse);
  });

  group('the / list', () {
    /// The labels of the / list's rows, top to bottom.
    List<String> rows(WidgetTester tester) {
      final names = [
        'Summarise',
        'Make it shorter',
        'Explain simply',
        'Make a list',
        'Translate',
        for (var i = 0; i < 7; i++) 'Mine $i',
        'Clear this chat',
      ];
      final shown = [
        for (final name in names)
          if (find.text(name).evaluate().isNotEmpty)
            (name, tester.getTopLeft(find.text(name)).dy),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      return [for (final (name, _) in shown) name];
    }

    testWidgets('lists the five built in, then Clear this chat, in the box', (
      tester,
    ) async {
      await pumpApp(tester, llm: planningServer());
      await tester.enterText(composerField, '/');
      await tester.pump();
      expect(rows(tester), [
        'Summarise',
        'Make it shorter',
        'Explain simply',
        'Make a list',
        'Translate',
        'Clear this chat',
      ]);
      // Straight in the message box's tile: its edge, 6 around the list and 20 in each row.
      final box = tester.getTopLeft(find.byType(Composer)).dx + 16;
      expect(tester.getTopLeft(find.text('Summarise')).dx, box + 1 + 6 + 20);
      final row = find.ancestor(
        of: find.text('Summarise'),
        matching: find.byType(ConstrainedBox),
      );
      expect(tester.getSize(row.first).height, 56);
    });

    testWidgets('comes back when the Add sheet closes, and Enter picks it', (
      tester,
    ) async {
      final llm = planningServer();
      await pumpApp(tester, llm: llm);
      await tester.enterText(composerField, '/su');
      await tester.pump();
      expect(rows(tester), ['Summarise']);
      await tester.tap(
        find.byTooltip('Add files or shortcuts to this message'),
      );
      await tester.pumpAndSettle();
      // Another tab rebuilds the message box while the sheet hides the list.
      await tester.tap(find.text('Shortcuts').last);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(rows(tester), ['Summarise']);
      await tester.tap(composerField);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
      expect(find.text('Summarise'), findsOneWidget);
    });

    testWidgets('/s keeps those that start so, /zz says it is sent as typed', (
      tester,
    ) async {
      await pumpApp(tester, llm: planningServer());
      await tester.enterText(composerField, '/s');
      await tester.pump();
      expect(rows(tester), ['Summarise', 'Make it shorter']);
      await tester.enterText(composerField, '/zz');
      await tester.pump();
      expect(rows(tester), isEmpty);
      expect(
        find.text('No shortcut called /zz. It is sent as typed.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'twelve scroll in the box, at most 290 tall, the person\'s after',
      (tester) async {
        final h = await pumpApp(tester, llm: planningServer());
        for (var i = 0; i < 7; i++) {
          await h.prefs.saveShortcut(
            PromptShortcut(
              id: 'mine-$i',
              name: 'mine$i',
              label: 'Mine $i',
              prompt: 'Do thing $i.',
            ),
          );
        }
        await tester.enterText(composerField, '/');
        await tester.pump();
        final list = find.descendant(
          of: find.byType(Composer),
          matching: find.byType(ListView),
        );
        expect(tester.getSize(list).height, lessThanOrEqualTo(290));
        expect(rows(tester).take(6), [
          'Summarise',
          'Make it shorter',
          'Explain simply',
          'Make a list',
          'Translate',
          'Mine 0',
        ]);
        await tester.drag(list, const Offset(0, -2000));
        await tester.pump();
        expect(rows(tester).last, 'Clear this chat');
        expect(tester.takeException(), isNull);
      },
    );
  });
}
