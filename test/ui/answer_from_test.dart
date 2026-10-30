import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/ui/chat/composer.dart';
import 'package:anywherellm/ui/widgets/sheet.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

Finder inComposer(Finder finder) =>
    find.descendant(of: find.byType(Composer), matching: finder);

/// The chip, whatever it names.
Finder get chip => find.byWidgetPredicate(
  (widget) => widget is Tappable && widget.label.startsWith('Answer from'),
);

Finder get menuNote => find.text('Applies to every chat in Q3 planning.');

Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(SheetFrame), matching: finder);

/// A mode's card in the sheet, by its title.
Finder mode(ChatMode mode) => inSheet(
  find.byWidgetPredicate(
    (w) => w is Tappable && w.label.startsWith('${mode.title}.'),
  ),
);

/// The planning server with its first workspace on Files & knowledge, so the chip shows.
FakeAnythingLlm onChat() =>
    planningServer()..spaces.first.settings['chatMode'] = 'chat';

void main() {
  testWidgets('the default mode and the system model have no chips', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer());
    expect(chip, findsNothing);
    expect(inComposer(find.text('Files, knowledge & tools')), findsNothing);
    expect(inComposer(find.text('qwen3:8b')), findsNothing);
  });

  testWidgets(
    'the composer names the chat mode in plain words, not the server',
    (tester) async {
      await pumpApp(tester, llm: onChat());
      expect(
        tester.widget<Tappable>(chip).label,
        'Answer from: Files & knowledge',
      );
      expect(inComposer(find.text('Files & knowledge')), findsOneWidget);
      expect(inComposer(find.textContaining('AnythingLLM')), findsNothing);
      expect(inComposer(find.text('Chat')), findsNothing);
      // The workspace answers with the system's model, so no model chip follows it.
      expect(inComposer(find.text('qwen3:8b')), findsNothing);
    },
  );

  testWidgets('the menu lists the modes and sets the workspace\'s mode', (
    tester,
  ) async {
    final llm = onChat();
    final h = await pumpApp(tester, llm: llm);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(h.shell.answerFromOpen, isTrue);
    expect(inSheet(find.text('Answer from')), findsOneWidget);
    for (final m in ChatMode.values) {
      expect(mode(m), findsOneWidget);
      expect(inSheet(find.text(m.detail)), findsOneWidget);
    }
    expect(menuNote, findsOneWidget);
    expect(tester.widget<Tappable>(mode(ChatMode.chat)).selected, isTrue);
    await tester.tap(mode(ChatMode.query));
    await tester.pumpAndSettle();
    expect(llm.spaces.first.settings['chatMode'], 'query');
    expect(h.sources.chatMode.value, ChatMode.query);
    expect(menuNote, findsNothing);
    expect(tester.widget<Tappable>(chip).label, 'Answer from: Files only');
    expect(find.text('Ask about your files…'), findsOneWidget);
    // Back on the default, the chip goes.
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(mode(ChatMode.automatic));
    await tester.pumpAndSettle();
    expect(llm.spaces.first.settings['chatMode'], 'automatic');
    expect(chip, findsNothing);
  });

  testWidgets('Files only tints the chip', (tester) async {
    final h = await pumpApp(tester, llm: onChat());
    Color? fill() => tester
        .widget<Material>(
          find.descendant(of: chip, matching: find.byType(Material)).first,
        )
        .color;
    expect(fill(), Colors.transparent);
    await h.sources.setChatMode(ChatMode.query);
    await tester.pumpAndSettle();
    expect(fill(), isNot(Colors.transparent));
  });

  testWidgets('Esc, Back and a tap above the sheet close it', (tester) async {
    final h = await pumpApp(tester, llm: onChat());
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(menuNote, findsNothing);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(menuNote, findsNothing);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(menuNote, findsNothing);
    expect(h.shell.answerFromOpen, isFalse);
  });

  testWidgets('the chip is off while an answer runs, which closes the menu', (
    tester,
  ) async {
    final llm = onChat()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await typeAndEnter(tester, 'Go');
    expect(h.shell.answerFromOpen, isFalse);
    expect(tester.widget<Tappable>(chip).onTap, isNull);
    await tester.tap(chip, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(menuNote, findsNothing);
  });

  testWidgets('another workspace closes the menu', (tester) async {
    final h = await pumpApp(tester, llm: onChat());
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await h.chat.select('household');
    await tester.pumpAndSettle();
    expect(h.shell.answerFromOpen, isFalse);
  });

  testWidgets('the sheet names the model, which nothing there changes', (
    tester,
  ) async {
    final llm = onChat();
    await pumpApp(tester, llm: llm);
    // No model chip in the row: the row has room for one.
    expect(inComposer(find.text('qwen3:8b')), findsNothing);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(menuNote, findsOneWidget);
    expect(inSheet(find.text('Chat model')), findsOneWidget);
    expect(inSheet(find.text('System default (qwen3:8b)')), findsOneWidget);
    // A row to read, not a control: a tap leaves the sheet open and writes nothing.
    expect(control('Chat model, System default (qwen3:8b)'), findsNothing);
    await tester.tap(inSheet(find.text('Chat model')));
    await tester.pumpAndSettle();
    expect(menuNote, findsOneWidget);
    expect(llm.calls.where((c) => c.startsWith('update')), isEmpty);
  });

  for (final size in const [Size(360, 480), Size(412, 915), Size(740, 360)]) {
    testWidgets(
      'the menu fits at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await pumpApp(tester, llm: onChat(), size: size);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        final choice = mode(ChatMode.query);
        await tester.ensureVisible(choice);
        await tester.pumpAndSettle();
        final menu = tester.getRect(choice);
        expect(menu.top, greaterThanOrEqualTo(0));
        expect(menu.right, lessThanOrEqualTo(size.width));
        expect(menu.bottom, lessThanOrEqualTo(size.height));
      },
    );
  }
}
