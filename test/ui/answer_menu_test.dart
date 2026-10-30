import 'package:anywherellm/core/outputs.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/widgets/sheet.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
import '../support/pump.dart';

const _more = 'More: read aloud, ask again, details';
const _details = 'Details: model, time, tokens, speed and cost';
const _always = 'Show details under every answer';

/// Opens the latest answer's Answer sheet, then This answer from its Details.
Future<void> openDetails(WidgetTester tester) async {
  await tester.tap(control(_more));
  await tester.pumpAndSettle();
  await tester.tap(control(_details));
  await tester.pumpAndSettle();
}

/// The answer drawn highest on screen whose words hold [text].
Finder topmost(WidgetTester tester, String text) {
  final all = find.textContaining(text, findRichText: true);
  final top = all.evaluate().reduce(
    (a, b) =>
        tester.getTopLeft(find.byElementPredicate((e) => e == a)).dy <=
            tester.getTopLeft(find.byElementPredicate((e) => e == b)).dy
        ? a
        : b,
  );
  return find.byElementPredicate((e) => e == top);
}

Future<void> ask(WidgetTester tester, String text) async {
  await tester.enterText(composerField, text);
  await tester.pump();
  await tester.tap(control('Send'));
  await tester.pumpAndSettle();
}

/// The server's answers, measured as the menu's board draws them, less the cost.
FakeAnythingLlm measured() => planningServer()
  ..measured = const AnswerMetrics(
    model: 'glm-5.3',
    tokens: 1642,
    seconds: 4.3,
    speed: 22.2,
  );

void main() {
  testWidgets('an answer not measured says nothing of how it ran', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer());
    await ask(tester, 'First');
    expect(find.textContaining('tokens'), findsNothing);
    await tester.tap(control(_more));
    await tester.pumpAndSettle();
    expect(control(_details), findsNothing);
  });

  testWidgets('More has no reasoning to show', (tester) async {
    await pumpApp(
      tester,
      llm: measured()..answer = '<think>Weighing the plan.</think>About 45k.',
    );
    await ask(tester, 'Budget?');
    expect(find.textContaining('Weighing the plan.'), findsNothing);
    await openDetails(tester);
    expect(find.text('glm-5.3'), findsOneWidget);
    expect(find.text('View reasoning'), findsNothing);
    expect(find.textContaining('Weighing the plan.'), findsNothing);
  });

  testWidgets('More follows Copy, and its Details lists what was measured', (
    tester,
  ) async {
    await pumpApp(tester, llm: measured());
    await ask(tester, 'Second');
    final more = control(_more);
    expect(more, findsOneWidget);
    expect(control('Retry'), findsNothing, reason: 'Ask again is in the sheet');
    // Nothing of how it ran shows until asked for.
    expect(find.textContaining('tok/s'), findsNothing);
    // Each control under the newest answer, the lowest of its kind.
    Offset at(String label) => control(label)
        .evaluate()
        .map((e) => tester.getTopLeft(find.byElementPredicate((x) => x == e)))
        .reduce((a, b) => a.dy >= b.dy ? a : b);
    final row = ['Copy answer', _more].map(at).toList();
    expect(row.map((o) => o.dy).toSet(), hasLength(1));
    final left = [for (final o in row) o.dx];
    expect(left, orderedEquals([...left]..sort()));
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.text('Answer'), findsOneWidget);
    for (final row in ['Copy answer', 'Select text', 'Ask again', _details]) {
      expect(
        find.descendant(of: find.byType(SheetFrame), matching: control(row)),
        findsOneWidget,
        reason: row,
      );
    }
    await tester.tap(control(_details));
    await tester.pumpAndSettle();
    expect(find.text('This answer'), findsOneWidget);
    for (final (name, value) in [
      ('Model', 'glm-5.3'),
      ('Time', '4.3 s'),
      ('Tokens', '1,642'),
      ('Speed', '22 tok/s'),
    ]) {
      expect(find.text(name), findsOneWidget);
      expect(find.text(value), findsOneWidget);
    }
    // No price, no Cost row.
    expect(find.text('Cost'), findsNothing);
    expect(find.text('Rate this answer'), findsNothing);
    expect(control('Good answer'), findsNothing);
    expect(control(_always), findsOneWidget);
  });

  testWidgets('More is a sheet, closed by Esc, Back and the scrim', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: measured());
    await ask(tester, 'Second');
    await openDetails(tester);
    final sheet = find.byType(SheetFrame);
    expect(
      find.descendant(of: sheet, matching: find.text('This answer')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('glm-5.3')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.shell.popup.value, isNull);
    expect(find.byType(SheetFrame), findsNothing);
    await tester.tap(control(_more));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.shell.popup.value, isNull);
    await tester.tap(control(_more));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195, 30));
    await tester.pumpAndSettle();
    expect(h.shell.popup.value, isNull);
  });

  testWidgets('the menu goes with its answer when another chat opens', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: measured());
    await ask(tester, 'Second');
    await tester.tap(control(_more));
    await tester.pumpAndSettle();
    await h.chat.open('priorities');
    await tester.pumpAndSettle();
    expect(find.byType(SheetFrame), findsNothing);
    expect(h.shell.popup.value, isNull);
  });

  testWidgets('the menu\'s switch shows the details under every answer', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: measured());
    await ask(tester, 'First');
    await ask(tester, 'Second');
    expect(control(_more), findsOneWidget, reason: 'the latest answer only');
    await openDetails(tester);
    await tester.tap(control(_always));
    await tester.pumpAndSettle();
    expect(h.prefs.prefs.isOn(ChatSwitch.answerDetails), isTrue);
    expect(h.prefsStore.saved.isOn(ChatSwitch.answerDetails), isTrue);
    expect(
      find.text('glm-5.3 · 1,642 tokens · 22 tok/s · 4.3 s'),
      findsNWidgets(2),
    );
    // It stays open, the switch on.
    final row = tester.widget<Tappable>(control(_always));
    expect(row.toggled, isTrue);
  });

  testWidgets('an older answer shows Copy and More once tapped', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer());
    await ask(tester, 'First');
    await ask(tester, 'Second');
    expect(control('Copy answer'), findsOneWidget);
    await tester.tap(topmost(tester, 'Here is what your sources say.'));
    await tester.pumpAndSettle();
    expect(control('Copy answer'), findsNWidgets(2));
    await tester.tap(topmost(tester, 'Here is what your sources say.'));
    await tester.pumpAndSettle();
    expect(control('Copy answer'), findsOneWidget);
  });

  testWidgets(
    'a long press opens the Answer sheet, whose Select text shows the words selectable',
    (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      await ask(tester, 'First');
      expect(find.byType(SelectableText), findsNothing);
      await tester.longPress(topmost(tester, 'Here is what your sources say.'));
      await tester.pumpAndSettle();
      expect(find.text('Answer'), findsOneWidget);
      await tester.tap(control('Select text'));
      await tester.pumpAndSettle();
      final sheet = find.byType(SheetFrame);
      expect(
        find.descendant(of: sheet, matching: find.text('Select text')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.byType(SelectableText)),
        findsWidgets,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.shell.popup.value, isNull);
    },
  );

  testWidgets('Settings\' Chat page has the same switch', (tester) async {
    final h = await pumpApp(
      tester,
      llm: measured(),
      prefsStore: FakePrefsStore(
        const Prefs().withSwitch(ChatSwitch.answerDetails, true),
      ),
    );
    await ask(tester, 'Second');
    expect(
      find.text('glm-5.3 · 1,642 tokens · 22 tok/s · 4.3 s'),
      findsOneWidget,
    );
    h.shell.openSettings(SettingsPage.chat);
    await tester.pumpAndSettle();
    await tester.tap(control('Show answer details'));
    await tester.pumpAndSettle();
    expect(h.prefs.prefs.isOn(ChatSwitch.answerDetails), isFalse);
    h.shell.closeSettings();
    await tester.pumpAndSettle();
    expect(find.textContaining('tok/s'), findsNothing);
  });
}
