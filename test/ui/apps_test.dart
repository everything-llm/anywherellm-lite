import 'package:anywherellm/core/apps.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/ui/apps/app_screen.dart';
import 'package:anywherellm/ui/apps/app_sheets.dart';
import 'package:anywherellm/ui/apps/apps_tab.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_apps.dart';
import '../support/pump.dart';

const _groceries = AppRef('q3', 'groceries');
const _page = 'https://h:8465/q3/groceries/';

/// The app's home, Chats tab, with the apps server beside it, Groceries in Q3 planning.
Future<Harness> _withApps(
  WidgetTester tester, {
  FakeAnythingLlm? llm,
  FakeApps? apps,
  bool onChat = false,
}) async {
  final h = await pumpApp(
    tester,
    llm: llm ?? planningServer(),
    appsServer: apps ?? groceriesServer(),
    canViewApps: true,
    onChat: onChat,
  );
  await tester.pumpAndSettle();
  return h;
}

/// Opens the Apps tab.
Future<void> _appsTab(WidgetTester tester) async {
  await tester.tap(control('Apps'));
  await tester.pumpAndSettle();
}

/// Opens Groceries and its data folder.
Future<void> _folder(WidgetTester tester, Harness h) async {
  h.shell.openApp(_groceries);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Data and history for Groceries'));
  await tester.pumpAndSettle();
}

void main() {
  group('beside a stock AnythingLLM', () {
    testWidgets('nothing about apps shows, and nothing more is asked', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: planningServer(), onChat: false);
      await tester.pumpAndSettle();
      expect(control('Chats'), findsOneWidget);
      expect(control('Apps'), findsNothing);
      expect(find.byType(AppsTab), findsNothing);
      expect(h.appsServer.calls, ['available']);
      expect(h.apps.available, isFalse);
    });
  });

  group('beside the apps server', () {
    testWidgets('the Apps tab lists the open workspace\'s apps', (
      tester,
    ) async {
      final h = await _withApps(tester);
      expect(control('Apps'), findsOneWidget);
      await _appsTab(tester);
      expect(find.byType(AppsTab), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.textContaining('List · 1 of 2 left · '), findsOneWidget);
      expect(h.appsServer.calls, contains('apps:q3'));

      // Another workspace's apps are read as it opens.
      await h.chat.select('household');
      await tester.pumpAndSettle();
      expect(h.appsServer.calls, contains('apps:household'));
      expect(find.text('No apps in this workspace yet.'), findsOneWidget);

      // Back goes to the Chats tab.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AppsTab), findsNothing);
    });

    testWidgets('the answer is remembered, and Test connection asks again', (
      tester,
    ) async {
      final h = await _withApps(tester);
      expect(h.appsServer.asked, 1);
      h.appsServer.present = false;
      await tester.tap(control('Settings'));
      await tester.pumpAndSettle();
      expect(h.appsServer.asked, 1);
      await h.settings.testSaved();
      await tester.pumpAndSettle();
      expect(h.appsServer.asked, 2);
      expect(h.apps.available, isFalse);
      expect(control('Apps'), findsNothing);
    });

    testWidgets('the Apps tab gives way to Chats when the server goes', (
      tester,
    ) async {
      final h = await _withApps(tester);
      await _appsTab(tester);
      h.appsServer.present = false;
      await h.settings.testSaved();
      await tester.pumpAndSettle();
      expect(find.byType(AppsTab), findsNothing);
      expect(find.text('Quarter priorities'), findsOneWidget);
    });

    testWidgets('an app opens full screen at the app\'s theme, and Back '
        'closes it', (tester) async {
      final h = await _withApps(tester);
      await _appsTab(tester);
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      expect(find.byType(AppScreen), findsOneWidget);
      expect(find.text('Web view of $_page?theme=light'), findsOneWidget);
      expect(find.text('List · Q3 planning'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(AppScreen), findsNothing);
      expect(find.byType(AppsTab), findsOneWidget);
      expect(h.shell.app, isNull);
    });

    testWidgets('without a web view an app shows its card and the way to its '
        'page', (tester) async {
      final h = await pumpApp(
        tester,
        llm: planningServer(),
        appsServer: groceriesServer(),
        onChat: false,
      );
      await tester.pumpAndSettle();
      h.shell.openApp(_groceries);
      await tester.pumpAndSettle();
      // The test's picture never decodes, so it has no size and counts as off the screen.
      expect(find.byType(Image, skipOffstage: false), findsOneWidget);
      await tester.tap(find.text('Open in the browser'));
      expect(h.opened, [Uri.parse('$_page?theme=light')]);
    });

    testWidgets('the data folder lists the files and the git history, never '
        'the caches', (tester) async {
      final h = await _withApps(tester);
      await _folder(tester, h);
      expect(find.text('apps/groceries/'), findsOneWidget);
      expect(find.text('3 files'), findsOneWidget);
      for (final file in ['app.json', 'log.jsonl', 'page.html', '.git']) {
        expect(find.text(file), findsOneWidget, reason: file);
      }
      expect(find.textContaining('2 commits'), findsOneWidget);
      expect(find.textContaining('.cache/'), findsOneWidget);

      // Back steps from the folder to the app, then closes it.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Web view of $_page?theme=light'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.shell.app, isNull);
    });

    testWidgets('app.json reads as JSON, or raw', (tester) async {
      final h = await _withApps(tester);
      await _folder(tester, h);
      await tester.tap(find.text('app.json'));
      await tester.pumpAndSettle();
      expect(find.text('about'), findsOneWidget);
      expect(find.text('A list of things to get.'), findsOneWidget);
      expect(
        find.text('Tick an item rather than removing it.'),
        findsOneWidget,
      );

      await tester.tap(control('Show the raw file'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"title":"Groceries"'), findsOneWidget);
      expect(find.text('about'), findsNothing);
    });

    testWidgets('page.html shows as text, never run', (tester) async {
      final h = await _withApps(tester);
      await _folder(tester, h);
      await tester.tap(find.text('page.html'));
      await tester.pumpAndSettle();
      expect(find.textContaining('<ul id="items"></ul>'), findsOneWidget);
      expect(find.text('2 lines · 51 B'), findsOneWidget);
      expect(control('Show the raw file'), findsNothing);
    });

    testWidgets('the log lists its lines newest first, and one shows the '
        'state after it, to restore', (tester) async {
      final h = await _withApps(tester);
      await _folder(tester, h);
      await tester.tap(find.text('log.jsonl'));
      await tester.pumpAndSettle();
      final titles = [
        for (final title in ['tick', 'add', 'made'])
          tester.getTopLeft(find.text(title)).dy,
      ];
      expect(titles, orderedEquals([...titles]..sort()));
      expect(find.text('text: Milk'), findsOneWidget);
      expect(find.text('Agent'), findsOneWidget);
      expect(find.text('The beginning'), findsOneWidget);

      await tester.tap(find.text('add'));
      await tester.pumpAndSettle();
      expect(find.text('State after this'), findsOneWidget);
      expect(h.appsServer.calls, contains('state:2'));
      expect(find.textContaining('"text": "Eggs"'), findsWidgets);

      await tapVisible(tester, find.text('Put the app back to this'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Restore'));
      await tester.pumpAndSettle();
      expect(h.appsServer.calls, contains('restore:2'));
      expect(find.text('State after this'), findsNothing);
      // The log is read again, with the restore as its newest line.
      expect(find.text('restore'), findsOneWidget);
      expect(find.text('to: 2'), findsOneWidget);
    });

    testWidgets('the newest line is the current state, with nothing to '
        'restore', (tester) async {
      final h = await _withApps(tester);
      await _folder(tester, h);
      await tester.tap(find.text('log.jsonl'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Current state'));
      await tester.pumpAndSettle();
      expect(find.text('Current state'), findsWidgets);
      expect(find.text('Put the app back to this'), findsNothing);
    });

    testWidgets('a raw log shows its lines numbered', (tester) async {
      final h = await _withApps(tester);
      await _folder(tester, h);
      await tester.tap(find.text('log.jsonl'));
      await tester.pumpAndSettle();
      await tester.tap(control('Show the raw file'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"ev":"tick"'), findsOneWidget);
      expect(find.text('1\n2\n3'), findsOneWidget);
    });

    testWidgets('a commit shows its diff, to revert', (tester) async {
      final h = await _withApps(tester);
      await _folder(tester, h);
      await tester.tap(find.text('.git'));
      await tester.pumpAndSettle();
      expect(find.text('5f6c11f'), findsOneWidget);
      expect(find.text('Make Groceries'), findsOneWidget);

      await tester.tap(find.text('Ticks move to the bottom'));
      await tester.pumpAndSettle();
      expect(find.text('commit 5f6c11f'), findsOneWidget);
      expect(find.textContaining('class="sorted"'), findsOneWidget);
      await tapVisible(tester, find.text('Revert this commit'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Revert'));
      await tester.pumpAndSettle();
      expect(
        h.appsServer.calls,
        contains('revert:5f6c11f0a1b2c3d4e5f60718293a4b5c6d7e8f90'),
      );
      expect(find.text('commit 5f6c11f'), findsNothing);
      expect(find.text('Revert "Ticks move to the bottom"'), findsOneWidget);
    });

    testWidgets('the first commit cannot be reverted, and a refused revert '
        'says why', (tester) async {
      final h = await _withApps(tester);
      h.appsServer.errors['revert'] = const ApiException(
        'That commit no longer reverts cleanly.',
      );
      await _folder(tester, h);
      await tester.tap(find.text('.git'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make Groceries'));
      await tester.pumpAndSettle();
      expect(find.text('Revert this commit'), findsNothing);
      h.shell.closePopup();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ticks move to the bottom'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Revert this commit'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Revert'));
      await tester.pumpAndSettle();
      expect(
        find.text('That commit no longer reverts cleanly.'),
        findsOneWidget,
      );
      expect(find.text('commit 5f6c11f'), findsOneWidget);
    });

    testWidgets('an app is renamed from its menu', (tester) async {
      final h = await _withApps(tester);
      await _appsTab(tester);
      await tester.tap(find.byTooltip('Open, rename or delete Groceries'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(find.textContaining('apps/groceries'), findsOneWidget);
      await tester.enterText(typingField(), 'Food');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(h.appsServer.calls, contains('rename:Food'));
      h.shell.closePopup();
      await tester.pumpAndSettle();
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
    });

    testWidgets('an app is deleted from its menu, after asking', (
      tester,
    ) async {
      final h = await _withApps(tester);
      await _appsTab(tester);
      await tester.tap(find.byTooltip('Open, rename or delete Groceries'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete app'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Delete Groceries?'), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(h.appsServer.calls, isNot(contains('delete:groceries')));

      await tester.tap(find.byTooltip('Open, rename or delete Groceries'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete app'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(h.appsServer.calls, contains('delete:groceries'));
      expect(find.text('No apps in this workspace yet.'), findsOneWidget);
    });

    testWidgets('a server that cannot list apps says why', (tester) async {
      final h = await _withApps(
        tester,
        apps: groceriesServer()
          ..errors['apps'] = const ApiException('The apps server is busy.'),
      );
      await _appsTab(tester);
      expect(find.text('Could not read the apps'), findsOneWidget);
      expect(find.text('The apps server is busy.'), findsOneWidget);
      expect(h.shell.tab, HomeTab.apps);
    });
  });

  group('every apps screen fits', () {
    const word =
        'an-extremely-long-unbroken-name-that-has-no-place-to-wrap-and-must-not-overflow';
    FakeApps awkward() {
      final apps = groceriesServer();
      final was = apps.spaces['q3']!.single;
      apps.spaces['q3'] = [
        ServerApp(
          ref: was.ref,
          title: 'title-$word',
          kind: 'custom-$word',
          summary: 'summary-$word',
          modified: was.modified,
          line: 3,
          page: was.page,
          card: was.card,
        ),
      ];
      apps.folders[_groceries]!['notes-$word.txt'] = 'line-$word';
      apps.commits[_groceries]!.first = AppCommit(
        commit: apps.commits[_groceries]!.first.commit,
        by: 'agent',
        chat: 'chat-$word',
        message: 'message-$word',
      );
      return apps;
    }

    for (final size in const [
      Size(412, 915),
      Size(360, 640),
      Size(740, 360),
      Size(360, 480),
    ]) {
      final at = '${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('at $at', (tester) async {
        final h = await pumpApp(
          tester,
          llm: planningServer(),
          appsServer: awkward(),
          canViewApps: true,
          onChat: false,
          size: size,
        );
        await tester.pumpAndSettle();
        await _appsTab(tester);
        h.shell.togglePopup(AppMenuSheet(_groceries));
        await tester.pumpAndSettle();
        h.shell.togglePopup(AppRenameSheet(_groceries));
        await tester.pumpAndSettle();
        h.shell.togglePopup(AppDeleteSheet(_groceries));
        await tester.pumpAndSettle();
        h.shell.closePopup();
        h.shell.openApp(_groceries, data: true);
        await tester.pumpAndSettle();
        for (final page in [
          const AppFileOf('app.json'),
          AppFileOf('notes-$word.txt'),
          const AppLog(),
          const AppGit(),
        ]) {
          h.shell.showAppPage(page);
          await tester.pumpAndSettle();
        }
        final commit = h.appsServer.commits[_groceries]!.first;
        h.shell.togglePopup(CommitSheet(_groceries, commit, first: false));
        await tester.pumpAndSettle();
        final lines = logLinesOf(
          h.appsServer.folders[_groceries]!['log.jsonl']!,
        );
        h.shell.togglePopup(LineSheet(_groceries, lines.last, latest: false));
        await tester.pumpAndSettle();
        h.shell.closePopup();
        h.shell.appBack();
        h.shell.appBack();
        h.shell.appBack();
        h.shell.appBack();
        h.shell.appBack();
        await tester.pumpAndSettle();
        expect(find.byType(AppScreen), findsOneWidget);
      });
    }
  });
}
