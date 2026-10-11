import 'package:anywherellm/core/chat_log.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/ui/settings/settings_dialog.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:anywherellm/core/embeds.dart';
import 'package:flutter/material.dart';
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
  testWidgets(
    'Settings lists this app\'s pages and the Server page, which lists the rest',
    (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      h.shell.openSettings();
      await tester.pumpAndSettle();
      expect(control('Connection'), findsOneWidget);
      expect(control('Appearance'), findsOneWidget);
      expect(control('Chat'), findsOneWidget);
      expect(control('Server'), findsOneWidget);
      // No switch, and the server's pages are not in the list but on the Server page.
      expect(control('All settings'), findsNothing);
      expect(control('Chat model'), findsNothing);
      await tapShown(tester, control('Server'));
      expect(h.shell.settingsPage, SettingsPage.server);
      expect(find.text('ANSWERS'), findsOneWidget);
      expect(find.text('FILES, VOICE AND IMAGES'), findsOneWidget);
      expect(find.text('SHARING AND RECORDS'), findsOneWidget);
      await tapShown(
        tester,
        control('Document storage, LanceDB \u00b7 796 passages'),
      );
      expect(h.shell.settingsPage, SettingsPage.storage);
      expect(find.text('Stored passages'), findsOneWidget);
      // The page open sits under Server in the list, and a link over its title goes back.
      expect(control('Document storage'), findsOneWidget);
      await tapShown(tester, control('Back to Server'));
      expect(h.shell.settingsPage, SettingsPage.server);
      expect(control('Document storage'), findsNothing);
    },
  );

  testWidgets(
    'the Server page folds what is not set up, the web page\'s pages and Advanced',
    (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      h.shell.openSettings(SettingsPage.server);
      await tester.pumpAndSettle();
      expect(control('Not set up (1)'), findsOneWidget);
      expect(control('Image generation, Set up'), findsNothing);
      expect(control('Skills and tools, Opens in the browser'), findsNothing);
      await tapShown(tester, control('Not set up (1)'));
      expect(control('Image generation, Set up'), findsOneWidget);
      await tapShown(tester, control('In AnythingLLM\'s web page (8)'));
      expect(control('Skills and tools, Opens in the browser'), findsOneWidget);
      expect(find.textContaining('rarely changed'), findsOneWidget);
      await tapShown(tester, control('Skills and tools, Opens in the browser'));
      expect(h.opened, isNotEmpty);
      await tapShown(tester, control('Advanced'));
      await tapShown(
        tester,
        control(
          'Server settings as JSON, Every setting, as the server stores it',
        ),
      );
      expect(h.shell.settingsPage, SettingsPage.json);
    },
  );

  testWidgets('searching finds a page by its name, its line or a field', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer());
    h.shell.openSettings();
    await tester.pumpAndSettle();
    final search = find.descendant(
      of: find.byType(SettingsDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(search, 'voice');
    await tester.pumpAndSettle();
    expect(find.text('RESULTS'), findsOneWidget);
    expect(control('Voice and speech'), findsOneWidget);
    expect(control('Connection'), findsNothing);
    // A field names the page it is on, and a page in the web page says so.
    await tester.enterText(search, 'telemetry');
    await tester.pumpAndSettle();
    expect(control('Privacy and data, Anonymous telemetry'), findsOneWidget);
    await tester.enterText(search, 'security');
    await tester.pumpAndSettle();
    expect(control('Security, In the browser'), findsOneWidget);
    await tester.enterText(search, 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('NOTHING MATCHES'), findsOneWidget);
    // A page found opens, and the search clears.
    await tester.enterText(search, 'appearance');
    await tester.pumpAndSettle();
    await tapShown(tester, control('Appearance'));
    expect(h.shell.settingsPage, SettingsPage.appearance);
    expect(find.text('RESULTS'), findsNothing);
    expect(control('Server'), findsOneWidget);
  });

  testWidgets('a provider page folds the fields that are rarely changed', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer());
    h.shell.openSettings(SettingsPage.chatModel);
    await tester.pumpAndSettle();
    final fold = find.textContaining('Advanced (');
    expect(fold, findsOneWidget);
    expect(find.text('Longest answer'), findsNothing);
    await tester.tap(fold);
    await tester.pumpAndSettle();
    expect(find.text('Context window'), findsOneWidget);
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
    // Two groups and no switch: this app's pages, then the server's one row.
    expect(find.text('Theme'), findsNothing);
    expect(find.text('Server'), findsOneWidget);
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
    await tester.tap(find.text('Server'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'What AnythingLLM runs with. Each row opens the page that changes it.',
      ),
      findsOneWidget,
    );
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
    await tester.tap(find.byTooltip('Back to the chat'));
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
    expect(scan.dy, lessThan(tester.getTopLeft(find.text('or sign in')).dy));
    expect(
      tester.getTopLeft(find.text('or sign in')).dy,
      lessThan(tester.getTopLeft(control('Sign in')).dy),
    );
    expect(control('Paste a key'), findsOneWidget);
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

  testWidgets('titles are semibold, larger than section heads', (
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
    expect(style('Settings').fontWeight, FontWeight.w600);
    expect(style('Settings').fontSize, 22);
    expect(style('Workspace chats').fontWeight, FontWeight.w600);
    expect(style('Workspace chats').fontSize, 26);
    expect(style('Export').fontSize, lessThan(22));
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

  testWidgets('the Server page names the workspace its widgets answer from', (
    tester,
  ) async {
    final llm = planningServer()
      ..embedList = const [
        Embed(
          uuid: 'a',
          workspace: 'Q3 planning',
          mode: EmbedMode.chat,
          enabled: true,
        ),
      ];
    final h = await pumpApp(tester, llm: llm);
    await h.system.readEmbeds();
    h.shell.openSettings(SettingsPage.server);
    await tester.pumpAndSettle();
    expect(find.text('1 widget, on Q3 planning'), findsOneWidget);
  });
}
