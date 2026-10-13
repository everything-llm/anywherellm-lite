import 'package:anywherellm/core/outputs.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/widgets/sheet.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
import '../support/pump.dart';

const _more = 'More for this answer: model, time, tokens, speed and cost';
const _always = 'Show details under every answer';

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
    expect(control(_more), findsNothing);
    expect(find.textContaining('tokens'), findsNothing);
  });

  testWidgets('More has no reasoning to show', (tester) async {
    await pumpApp(
      tester,
      llm: measured()..answer = '<think>Weighing the plan.</think>About 45k.',
    );
    await ask(tester, 'Budget?');
    expect(find.textContaining('Weighing the plan.'), findsNothing);
    await tester.tap(control(_more));
    await tester.pumpAndSettle();
    expect(find.text('glm-5.3'), findsOneWidget);
    expect(find.text('View reasoning'), findsNothing);
    expect(find.textContaining('Weighing the plan.'), findsNothing);
  });

  testWidgets('More follows Copy and Retry, and lists what was measured', (
    tester,
  ) async {
    await pumpApp(tester, llm: measured());
    await ask(tester, 'Second');
    final more = control(_more);
    expect(more, findsOneWidget);
    // Nothing of how it ran shows until asked for.
    expect(find.textContaining('tok/s'), findsNothing);
    // Each control under the newest answer, the lowest of its kind.
    Offset at(String label) => control(label)
        .evaluate()
        .map((e) => tester.getTopLeft(find.byElementPredicate((x) => x == e)))
        .reduce((a, b) => a.dy >= b.dy ? a : b);
    final row = ['Copy answer', 'Retry', _more].map(at).toList();
    expect(row.map((o) => o.dy).toSet(), hasLength(1));
    final left = [for (final o in row) o.dx];
    expect(left, orderedEquals([...left]..sort()));
    await tester.tap(more);
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
    await tester.tap(control(_more));
    await tester.pumpAndSettle();
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
    expect(h.shell.answerMenu, isNull);
    expect(find.byType(SheetFrame), findsNothing);
    await tester.tap(control(_more));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.shell.answerMenu, isNull);
    await tester.tap(control(_more));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195, 30));
    await tester.pumpAndSettle();
    expect(h.shell.answerMenu, isNull);
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
    expect(find.text('This answer'), findsNothing);
    expect(h.shell.answerMenu, isNull);
  });

  testWidgets('the menu\'s switch shows the details under every answer', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: measured());
    await ask(tester, 'First');
    await ask(tester, 'Second');
    await tester.tap(control(_more).last);
    await tester.pumpAndSettle();
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
