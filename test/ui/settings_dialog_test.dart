import 'package:anywherellm/core/chat_log.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/ui/settings/settings_dialog.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
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
    expect(find.textContaining('more)'), findsNothing);
    await tester.tap(control('All settings'));
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

  testWidgets('Connection says how the server signs in and finds the relay', (
    tester,
  ) async {
    final llm = planningServer()
      ..auth = ServerAuth.password
      ..relay = true;
    final h = await pumpApp(tester, llm: llm);
    h.shell.openSettings(SettingsPage.connection);
    await tester.pumpAndSettle();
    expect(find.text('Background answers'), findsOneWidget);
    expect(
      find.text('Provided by the everythingllm relay on the server.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Available. Answers keep running after the app lets go of them.',
      ),
      findsOneWidget,
    );
    expect(find.text('AnythingLLM, single user, password on'), findsOneWidget);
    expect(find.text('Connected'), findsNothing);
    llm.verifyError = const ApiException('The server rejected the key.');
    await tapVisible(tester, control('Test connection'));
    await tester.pumpAndSettle();
    expect(find.text('The server rejected the key.'), findsOneWidget);
    expect(find.text('Connected'), findsNothing);
    llm.verifyError = null;
    await tapVisible(tester, control('Test connection'));
    await tester.pumpAndSettle();
    expect(find.text('Connected to h.'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    // Another page and back starts again from Saved.
    h.shell.showSettingsPage(SettingsPage.appearance);
    await tester.pumpAndSettle();
    h.shell.showSettingsPage(SettingsPage.connection);
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsNothing);
    expect(find.text('Saved'), findsWidgets);
  });

  testWidgets('a relay that is not there says answers come straight', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer()..relay = false);
    h.shell.openSettings(SettingsPage.connection);
    await tester.pumpAndSettle();
    expect(
      find.text('Not available. Answers come straight from AnythingLLM.'),
      findsOneWidget,
    );
  });

  testWidgets('titles are in the serif, section heads in the sans', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer());
    h.shell.openSettings(SettingsPage.chats);
    await tester.pumpAndSettle();
    // The last of a name is the page's own title, after the list of pages.
    TextStyle style(String text) => tester
        .widget<Text>(
          find
              .descendant(
                of: find.byType(SettingsDialog),
                matching: find.text(text),
              )
              .last,
        )
        .style!;
    expect(style('Settings').fontFamily, 'Instrument Serif');
    expect(style('Settings').fontSize, 28);
    expect(style('Workspace chats').fontFamily, 'Instrument Serif');
    expect(style('Workspace chats').fontSize, 32);
    expect(style('Export').fontFamily, 'Instrument Sans');
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
    expect(find.text('PROMPT'), findsOneWidget);
    final xs = [
      for (final label in ['CSV', 'JSON', 'JSONL', 'JSON (Alpaca)'])
        tester.getTopLeft(control(label)).dx,
    ];
    expect(xs, [...xs]..sort(), reason: 'the export buttons in that order');
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
