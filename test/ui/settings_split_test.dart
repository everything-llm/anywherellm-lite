import 'dart:ui';

import 'package:anywherellm/ui/settings/connection_page.dart';
import 'package:anywherellm/ui/settings/device_pages.dart';
import 'package:anywherellm/ui/settings/privacy_page.dart';
import 'package:anywherellm/ui/settings/server_page.dart';
import 'package:anywherellm/ui/settings/settings_dialog.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart' show AxisDirection, Scrollable;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

const desktop = Size(1440, 900);
const tablet = Size(960, 600);

/// [finder] in Settings.
Finder inSettings(Finder finder) =>
    find.descendant(of: find.byType(SettingsDialog), matching: finder);

/// Settings' row named [name], heard with the line under it.
Finder row(String name) => inSettings(
  find.byWidgetPredicate(
    (w) => w is Tappable && (w.label == name || w.label.startsWith('$name, ')),
  ),
);

/// Whether a screen reader hears Settings' row [name] as the one chosen.
bool chosen(WidgetTester tester, String name) =>
    tester.getSemantics(row(name).first).flagsCollection.isSelected ==
    Tristate.isTrue;

void main() {
  for (final (size, scale) in [(desktop, 1.0), (tablet, 1.0), (tablet, 2.0)]) {
    testWidgets(
      'every Settings page fits beside the list at '
      '${size.width.toInt()}x${size.height.toInt()}, ${(scale * 100).toInt()}% text',
      (tester) async {
        final dispatcher = tester.platformDispatcher;
        dispatcher.textScaleFactorTestValue = scale;
        addTearDown(dispatcher.clearTextScaleFactorTestValue);
        final h = await pumpApp(
          tester,
          llm: planningServer(),
          size: size,
          canDictate: true,
          canSpeak: true,
        );
        h.shell.openSettings();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final page in SettingsPage.values) {
          h.shell.showSettingsPage(page);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: page.name);
          await tester.drag(
            find
                .byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                )
                .last,
            const Offset(0, -2000),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: page.name);
        }
      },
    );
  }

  testWidgets('the first run fits beside the list', (tester) async {
    final h = await pumpApp(tester, connection: null, size: tablet);
    h.shell.openSettings(SettingsPage.connection);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ConnectionPage), findsOneWidget);
  });

  testWidgets('Settings opens on Connection beside its list', (tester) async {
    final h = await pumpApp(
      tester,
      llm: planningServer(),
      size: desktop,
    );
    h.shell.openSettings();
    await tester.pumpAndSettle();

    expect(inSettings(find.byType(Scrollable)), findsWidgets);
    expect(find.byType(ConnectionPage), findsOneWidget);
    expect(chosen(tester, 'Connection'), isTrue);
    expect(chosen(tester, 'Appearance'), isFalse);
  });

  testWidgets('a row shows its page beside the list', (tester) async {
    final h = await pumpApp(
      tester,
      llm: planningServer(),
      size: desktop,
    );
    h.shell.openSettings();
    await tester.pumpAndSettle();

    await tester.tap(inSettings(control('Appearance')));
    await tester.pumpAndSettle();

    expect(find.byType(AppearancePage), findsOneWidget);
    expect(find.byType(ConnectionPage), findsNothing);
    expect(chosen(tester, 'Appearance'), isTrue);
    // The list stays beside it.
    expect(inSettings(control('Connection')), findsOneWidget);
  });

  testWidgets('a page with a parent goes back to it, then Settings closes', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      llm: planningServer(),
      size: desktop,
    );
    h.shell.openSettings(SettingsPage.server);
    await tester.pumpAndSettle();
    h.shell.showSettingsPage(SettingsPage.privacy);
    await tester.pumpAndSettle();

    expect(find.byType(PrivacyPage), findsOneWidget);
    // Privacy and data marks the row it is reached from.
    expect(chosen(tester, 'Server'), isTrue);

    await tester.tap(inSettings(control('Back to Server')));
    await tester.pumpAndSettle();
    expect(find.byType(ServerPage), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
  });

  testWidgets('Esc from a page picked in the list closes Settings', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer(), size: tablet);
    h.shell.openSettings();
    await tester.pumpAndSettle();
    await tester.tap(inSettings(control('Chat')));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
  });

  testWidgets('with the shelf, a back arrow gives back the chat', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer(), size: tablet);
    h.shell.openSettings();
    await tester.pumpAndSettle();

    await tester.tap(inSettings(control('Back to the chat')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
  });

  testWidgets('beside the sidebar there is no back arrow', (tester) async {
    final h = await pumpApp(tester, llm: planningServer(), size: desktop);
    h.shell.openSettings();
    await tester.pumpAndSettle();

    expect(inSettings(control('Back to the chat')), findsNothing);
  });

  testWidgets('a phone keeps the list and its pages one at a time', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      llm: planningServer(),
      size: const Size(800, 900),
    );
    h.shell.openSettings();
    await tester.pumpAndSettle();

    expect(find.byType(ConnectionPage), findsNothing);
    await tester.tap(row('Server').first);
    await tester.pumpAndSettle();
    expect(h.shell.settingsPage, SettingsPage.server);
    expect(h.shell.settingsOpen, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.shell.settingsPage, isNull);
    expect(h.shell.settingsOpen, isTrue);
  });
}
