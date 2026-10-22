import 'package:anywherellm/ui/tokens.dart';
import 'package:anywherellm/ui/type.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
import '../support/pump.dart';

ThemeMode themeMode(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

void main() {
  testWidgets('the theme follows the system until one is picked, and is kept', (
    tester,
  ) async {
    final store = FakePrefsStore();
    final h = await pumpApp(tester, llm: planningServer(), prefsStore: store);
    expect(themeMode(tester), ThemeMode.system);
    h.shell.openSettings(SettingsPage.appearance);
    await tester.pumpAndSettle();
    await tester.ensureVisible(control('Dark'));
    await tester.pumpAndSettle();
    await tester.tap(control('Dark'));
    await tester.pumpAndSettle();
    expect(themeMode(tester), ThemeMode.dark);
    expect(store.saved.theme, ThemePref.dark);
    await tester.tap(control('Light'));
    await tester.pumpAndSettle();
    expect(themeMode(tester), ThemeMode.light);
  });

  testWidgets('a saved theme applies at start', (tester) async {
    await pumpApp(
      tester,
      llm: planningServer(),
      prefsStore: FakePrefsStore(const Prefs(theme: ThemePref.dark)),
    );
    expect(themeMode(tester), ThemeMode.dark);
  });

  testWidgets('the chat text size scales the turns and not the controls', (
    tester,
  ) async {
    final store = FakePrefsStore();
    final h = await pumpApp(tester, llm: planningServer(), prefsStore: store);
    double answerScale() => MediaQuery.textScalerOf(
      tester.element(find.text('About 40k.', skipOffstage: false)),
    ).scale(10);
    expect(answerScale(), 10);
    h.shell.openSettings(SettingsPage.appearance);
    await tester.pumpAndSettle();
    await tester.ensureVisible(control('Large'));
    await tester.pumpAndSettle();
    await tester.tap(control('Large'));
    await tester.pumpAndSettle();
    expect(store.saved.textSize, TextSize.large);
    expect(answerScale(), closeTo(12, 0.001));
    // The page sets a line at the size chosen, so the choice can be judged on it.
    final preview = tester.widget<Text>(
      find.text('An answer in the chat reads like this.'),
    );
    expect(preview.style!.fontSize, closeTo(Type.chat * 1.2, 0.001));
    final settings = MediaQuery.textScalerOf(
      tester.element(find.text('Chat text size')),
    );
    expect(settings.scale(10), 10);
  });

  test('the chosen segment is lighter than its track, in light and dark', () {
    // The chosen segment is a tile on the sunken track.
    for (final t in [Tokens.light, Tokens.dark]) {
      expect(
        t.tile.computeLuminance(),
        greaterThan(t.sunken.computeLuminance()),
      );
    }
  });
}
