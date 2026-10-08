import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/ui/chat/composer.dart';
import 'package:anywherellm/ui/chat/model_picker.dart';
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

const phone = Size(390, 844);

void main() {
  testWidgets(
    'the composer names the chat mode in plain words, not the server',
    (tester) async {
      await pumpApp(tester, llm: planningServer());
      expect(
        tester.widget<Tappable>(chip).label,
        'Answer from: Files, knowledge & tools',
      );
      expect(inComposer(find.text('Files, knowledge & tools')), findsOneWidget);
      expect(inComposer(find.textContaining('AnythingLLM')), findsNothing);
      expect(inComposer(find.text('Agent')), findsNothing);
      // The model chip follows it on a desktop.
      expect(inComposer(find.text('qwen3:8b')), findsOneWidget);
    },
  );

  testWidgets('the menu lists the modes and sets the workspace\'s mode', (
    tester,
  ) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(h.shell.answerFromOpen, isTrue);
    expect(find.text('ANSWER FROM'), findsOneWidget);
    for (final mode in ChatMode.values) {
      expect(control(mode.title), findsOneWidget);
      expect(find.text(mode.detail), findsOneWidget);
    }
    expect(menuNote, findsOneWidget);
    expect(
      tester.widget<Tappable>(control(ChatMode.automatic.title)).selected,
      isTrue,
    );
    await tester.tap(control('Files only'));
    await tester.pumpAndSettle();
    expect(llm.spaces.first.settings['chatMode'], 'query');
    expect(h.sources.chatMode.value, ChatMode.query);
    expect(menuNote, findsNothing);
    expect(tester.widget<Tappable>(chip).label, 'Answer from: Files only');
    expect(find.text('Ask about your files…'), findsOneWidget);
  });

  testWidgets('Files only tints the chip', (tester) async {
    final h = await pumpApp(tester, llm: planningServer());
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

  testWidgets('Esc, a tap outside and the chip again close the menu', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer());
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(menuNote, findsNothing);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(640, 200));
    await tester.pumpAndSettle();
    expect(menuNote, findsNothing);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(menuNote, findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(menuNote, findsNothing);
    expect(h.shell.answerFromOpen, isFalse);
  });

  testWidgets('the chip is off while an answer runs, which closes the menu', (
    tester,
  ) async {
    final llm = planningServer()..hold = true;
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
    final h = await pumpApp(tester, llm: planningServer());
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await h.chat.select('household');
    await tester.pumpAndSettle();
    expect(h.shell.answerFromOpen, isFalse);
  });

  testWidgets('on a phone the menu holds the model, which opens the picker', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer(), size: phone);
    // No model chip in the row: the row has room for one.
    expect(inComposer(find.text('qwen3:8b')), findsNothing);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(
      find.text('Both apply to every chat in Q3 planning.'),
      findsOneWidget,
    );
    expect(menuNote, findsNothing);
    await tester.tap(control('Chat model, qwen3:8b'));
    await tester.pumpAndSettle();
    expect(find.byType(ModelPicker), findsOneWidget);
    expect(find.text('Both apply to every chat in Q3 planning.'), findsNothing);
  });

  for (final size in const [Size(360, 480), Size(780, 700), Size(1400, 900)]) {
    testWidgets(
      'the menu fits at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await pumpApp(tester, llm: planningServer(), size: size);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        final menu = tester.getRect(control('Files only'));
        expect(menu.top, greaterThanOrEqualTo(0));
        expect(menu.right, lessThanOrEqualTo(size.width));
        expect(
          menu.bottom,
          lessThanOrEqualTo(tester.getRect(find.byType(Composer)).top),
        );
      },
    );
  }
}
