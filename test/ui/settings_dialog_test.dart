import 'package:anywherellm/core/chat_log.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/ui/settings/settings_dialog.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// Taps [finder], scrolling it into view first.
Future<void> tapShown(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// A control in Settings, by the label a screen reader hears.
Finder control(String label) => find.descendant(
  of: find.byType(SettingsDialog),
  matching: find.byWidgetPredicate(
    (widget) => widget is Tappable && widget.label == label,
  ),
);

const phone = Size(360, 640);

void main() {
  testWidgets('a provider page folds the fields that are rarely changed', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer());
    h.shell.openSettings(SettingsPage.chatModel);
    await tester.pumpAndSettle();
    final fold = find.textContaining('Advanced (');
    expect(fold, findsOneWidget);
    expect(find.text('Longest answer'), findsNothing);
    await tapShown(tester, fold);
    expect(find.text('Context window'), findsOneWidget);
  });

  testWidgets('with no server, only this device\'s pages show', (tester) async {
    final h = await pumpApp(tester, llm: planningServer(), connection: null);
    // A server's page opens on connecting instead.
    h.shell.openSettings(SettingsPage.chatModel);
    await tester.pumpAndSettle();
    expect(control('Connect'), findsOneWidget);
    h.shell.openSettings();
    await tester.pumpAndSettle();
    expect(control('Appearance'), findsOneWidget);
    expect(control('Server'), findsNothing);
  });

  testWidgets('on a phone, the list opens a page, and Back returns to it', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer(), size: phone);
    h.shell.openSettings();
    await tester.pumpAndSettle();
    // Two groups and no switch: this app's pages, then the server's one row.
    expect(find.text('Theme'), findsNothing);
    expect(find.text('Server', skipOffstage: false), findsOneWidget);
    expect(find.text('Chat model'), findsNothing);
    expect(control('All settings'), findsNothing);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Theme'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.shell.settingsOpen, isTrue);
    expect(h.shell.settingsPage, isNull);
    // Server lists the server's pages, and each goes back to it.
    await tapVisible(tester, find.text('Server', skipOffstage: false));
    await tester.pumpAndSettle();
    expect(h.shell.settingsPage, SettingsPage.server);
    await tester.tap(find.text('Chat model'));
    await tester.pumpAndSettle();
    expect(h.shell.settingsPage, SettingsPage.chatModel);
    await tester.tap(find.byTooltip('Back to Server'));
    await tester.pumpAndSettle();
    expect(h.shell.settingsPage, SettingsPage.server);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.shell.settingsPage, isNull);
    // The list is a tab: Back gives the Chats tab back.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.shell.settingsOpen, isFalse);
  });

  testWidgets('a phone\'s first run offers Scan QR code first', (tester) async {
    final h = await pumpApp(
      tester,
      size: phone,
      connection: null,
      canScan: true,
    );
    // As the app opens it at a start with nothing saved.
    h.shell.openSettings(SettingsPage.connection);
    await tester.pumpAndSettle();
    expect(find.textContaining('Connect to your'), findsOneWidget);
    final scan = tester.getTopLeft(control('Scan QR code'));
    expect(
      scan.dy,
      lessThan(tester.getTopLeft(find.text('OR ENTER A KEY')).dy),
    );
    expect(
      tester.getTopLeft(find.text('OR ENTER A KEY')).dy,
      lessThan(tester.getTopLeft(control('Connect')).dy),
    );
    expect(control('Paste a key'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone the camera fills the window, and Back stops it', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      size: phone,
      connection: null,
      canScan: true,
    );
    h.shell.openSettings(SettingsPage.connection);
    await tester.pumpAndSettle();
    await tester.tap(control('Scan QR code'));
    await tester.pumpAndSettle();
    expect(h.shell.scanning, isTrue);
    expect(find.text('Fake scan'), findsOneWidget);
    expect(find.textContaining('choose Connect a phone'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.shell.scanning, isFalse);
    expect(find.text('Fake scan'), findsNothing);
    expect(h.shell.settingsOpen, isTrue);
  });

  testWidgets('Test connection says whether the key still opens the server', (
    tester,
  ) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm);
    h.shell.openSettings(SettingsPage.connection);
    await tester.pumpAndSettle();
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

  testWidgets('workspace chats show a page, then more, and export', (
    tester,
  ) async {
    final llm = planningServer()
      ..chatLog = [
        for (var i = 25; i > 0; i--)
          LoggedChat(workspace: 'Household', question: 'Question $i'),
      ];
    final h = await pumpApp(tester, llm: llm, size: const Size(740, 900));
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

  testWidgets("a phone's Settings opens on the server, which it can test", (
    tester,
  ) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm);
    h.shell.openSettings();
    await tester.pumpAndSettle();
    expect(find.text('AnythingLLM'), findsWidgets);
    expect(find.text('Connected'), findsOneWidget);
    await tester.tap(control('Test connection'));
    await tester.pumpAndSettle();
    expect(llm.verified, hasLength(1));
    expect(find.text('Connected'), findsOneWidget);
  });
}
