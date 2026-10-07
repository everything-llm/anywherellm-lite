import 'package:anywherellm/core/chat_log.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/ui/settings/settings_dialog.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// A control in Settings, by the label a screen reader hears.
Finder control(String label) => find.descendant(
  of: find.byType(SettingsDialog),
  matching: find.byWidgetPredicate(
    (widget) => widget is Tappable && widget.label == label,
  ),
);

const phone = Size(360, 640);

void main() {
  testWidgets('Settings lists the essentials, and every page on asking', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer());
    h.shell.openSettings();
    await tester.pumpAndSettle();
    expect(find.text('Connection'), findsWidgets);
    expect(control('Chat model'), findsOneWidget);
    expect(control('Privacy and data'), findsOneWidget);
    expect(control('Document storage'), findsNothing);
    await tester.tap(control('All settings (8 more)'));
    await tester.pumpAndSettle();
    expect(control('Document storage'), findsOneWidget);
    expect(control('Website chat widgets'), findsOneWidget);
    await tester.tap(control('Document storage'));
    await tester.pumpAndSettle();
    expect(h.shell.settingsPage, SettingsPage.storage);
    expect(find.text('Stored passages'), findsOneWidget);
    // Back to the essentials leaves a page that is not one.
    await tester.tap(control('Essentials'));
    await tester.pumpAndSettle();
    expect(h.shell.settingsPage, SettingsPage.connection);
  });

  testWidgets('with no server, only this device\'s pages show', (tester) async {
    final h = await pumpApp(tester, llm: planningServer(), connection: null);
    h.shell.openSettings(SettingsPage.chatModel);
    await tester.pumpAndSettle();
    expect(control('Chat model'), findsNothing);
    expect(control('All settings'), findsNothing);
    expect(control('Appearance'), findsOneWidget);
    expect(find.text('AnythingLLM server'), findsOneWidget);
  });

  testWidgets('on a phone, the list opens a page, and Back returns to it', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer(), size: phone);
    h.shell.openSettings();
    await tester.pumpAndSettle();
    expect(find.text('Theme'), findsNothing);
    await tester.tap(control('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Theme'), findsOneWidget);
    expect(control('Chat model'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.shell.settingsOpen, isTrue);
    expect(control('Chat model'), findsOneWidget);
    await tester.tap(control('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('All settings'));
    await tester.pumpAndSettle();
    expect(control('Appearance'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.shell.settingsOpen, isFalse);
  });

  testWidgets('the composer opens Connection, even on a phone', (tester) async {
    final h = await pumpApp(tester, llm: planningServer(), size: phone);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Tappable && w.label == 'AnythingLLM settings, server h',
      ),
    );
    await tester.pumpAndSettle();
    expect(h.shell.settingsPage, SettingsPage.connection);
    expect(find.text('AnythingLLM server'), findsOneWidget);
  });

  testWidgets('Connection says how the server signs in and finds the relay', (
    tester,
  ) async {
    final llm = planningServer()
      ..auth = ServerAuth.password
      ..relay = true;
    final h = await pumpApp(tester, llm: llm);
    h.shell.openSettings(SettingsPage.connection);
    await tester.pumpAndSettle();
    expect(
      find.text('Found. Answers keep running after the app lets go of them.'),
      findsOneWidget,
    );
    expect(find.text('AnythingLLM, single user, password on'), findsOneWidget);
    llm.verifyError = const ApiException('The server rejected the key.');
    await tapVisible(tester, control('Test connection'));
    await tester.pumpAndSettle();
    expect(find.text('The server rejected the key.'), findsOneWidget);
    llm.verifyError = null;
    await tapVisible(tester, control('Test connection'));
    await tester.pumpAndSettle();
    expect(find.text('Connected to h.'), findsOneWidget);
  });

  testWidgets('a relay that cannot be asked says so', (tester) async {
    final llm = planningServer()
      ..errors['relayFound'] = const ApiException('Down');
    final h = await pumpApp(tester, llm: llm);
    h.shell.openSettings(SettingsPage.connection);
    await tester.pumpAndSettle();
    expect(find.text('Could not check.'), findsOneWidget);
  });

  testWidgets('workspace chats show a page, then more, and export', (
    tester,
  ) async {
    final llm = planningServer()
      ..chatLog = [
        for (var i = 25; i > 0; i--)
          LoggedChat(workspace: 'Household', question: 'Question $i'),
      ];
    final h = await pumpApp(tester, llm: llm, size: const Size(1400, 900));
    h.saveChosen = false;
    h.shell.openSettings(SettingsPage.chats);
    await tester.pumpAndSettle();
    expect(find.text('Question 25'), findsOneWidget);
    expect(find.text('Question 1'), findsNothing);
    await tapVisible(tester, control('Show more'));
    await tester.pumpAndSettle();
    expect(find.text('Question 1'), findsOneWidget);
    expect(control('Show more'), findsNothing);
    await tapVisible(tester, control('JSON'));
    await tester.pumpAndSettle();
    expect(llm.calls, isNot(contains(startsWith('exportChats'))));
    h.saveChosen = true;
    await tapVisible(tester, control('JSON'));
    await tester.pumpAndSettle();
    expect(
      String.fromCharCodes(h.saved['anythingllm-chats.json']!),
      llm.exported,
    );
    expect(find.text('Saved to /saved/anythingllm-chats.json'), findsOneWidget);
  });

  testWidgets('an export that cannot be saved says why on the page', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer());
    h.saveThrows = Exception('Disk full');
    h.shell.openSettings(SettingsPage.chats);
    await tester.pumpAndSettle();
    await tapVisible(tester, control('CSV'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save the chats'), findsOneWidget);
    expect(find.text('Disk full'), findsOneWidget);
  });
}
