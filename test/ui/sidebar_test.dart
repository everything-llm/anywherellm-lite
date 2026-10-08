import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/quick_switcher.dart';
import 'package:anywherellm/ui/sidebar.dart';
import 'package:anywherellm/ui/widgets/robin_mark.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
import '../support/pump.dart';

Finder inSidebar(Finder finder) =>
    find.descendant(of: find.byType(Sidebar), matching: finder);

Finder get search => find.bySemanticsLabel('Search workspaces and chats');

/// The server the fakes stand for, as the prefs key it.
const _server = 'https://h:3001';

/// The workspace names in the open menu, top to bottom.
List<String> order(WidgetTester tester) {
  final rows = [
    for (final name in ['Q3 planning', 'Household'])
      (name, tester.getTopLeft(control(name).last).dy),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final (name, _) in rows) name];
}

/// The top edge of [text] in the sidebar.
double top(WidgetTester tester, String text) => tester
    .getTopLeft(inSidebar(find.textContaining(text, findRichText: true)).first)
    .dy;

Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
  await tester.pumpAndSettle();
}

/// [planningServer] with four chats in Q3 planning, newest last.
FakeAnythingLlm fourChats() {
  final llm = planningServer();
  llm.spaces[0].threads.addAll(const [
    Thread(slug: 'offsite', name: 'Offsite venues'),
    Thread(slug: 'kickoff', name: 'Kickoff agenda'),
  ]);
  llm.histories['offsite'] = const [];
  llm.histories['kickoff'] = const [];
  return llm;
}

void main() {
  group('search', () {
    testWidgets('keeps the workspaces and chats that match', (tester) async {
      await pumpApp(tester, llm: planningServer());
      await tester.enterText(search, 'budget');
      await tester.pumpAndSettle();
      // Q3 planning stays for its chat; Household and the other chat go.
      expect(inSidebar(control('Q3 planning')), findsOneWidget);
      expect(inSidebar(control('Budget questions')), findsOneWidget);
      expect(inSidebar(control('Household')), findsNothing);
      expect(inSidebar(control('Quarter priorities')), findsNothing);
      expect(inSidebar(control('New chat')), findsNothing);
    });

    testWidgets('matches a workspace name without its chats', (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      await tester.enterText(search, 'HOUSE');
      await tester.pumpAndSettle();
      expect(inSidebar(control('Household')), findsOneWidget);
      expect(inSidebar(control('Q3 planning')), findsNothing);
      await tester.tap(inSidebar(control('Household')));
      await tester.pumpAndSettle();
      expect(h.chat.activeSlug, 'household');
    });

    testWidgets('says when nothing matches, and clearing brings it all back', (
      tester,
    ) async {
      await pumpApp(tester, llm: planningServer());
      await tester.enterText(search, 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches "zzz".'), findsOneWidget);
      await tester.tap(control('Clear search'));
      await tester.pumpAndSettle();
      expect(inSidebar(control('Budget questions')), findsOneWidget);
      expect(inSidebar(control('Quarter priorities')), findsOneWidget);
      expect(inSidebar(control('New chat')), findsOneWidget);
    });

    testWidgets('a chat of another workspace opens that workspace', (
      tester,
    ) async {
      final llm = planningServer();
      llm.spaces[1].threads.add(const Thread(slug: 'chores', name: 'Chores'));
      llm.histories['chores'] = const [];
      final h = await pumpApp(tester, llm: llm);
      expect(h.chat.activeSlug, 'q3');
      await tester.enterText(search, 'chores');
      await tester.pumpAndSettle();
      await tester.tap(inSidebar(control('Chores')));
      await tester.pumpAndSettle();
      expect(h.chat.activeSlug, 'household');
      expect(h.chat.activeThread, 'chores');
    });

    testWidgets('an older chat of another workspace reads only that chat', (
      tester,
    ) async {
      final llm = planningServer();
      llm.spaces[1].threads.addAll(const [
        Thread(slug: 'chores', name: 'Chores'),
        Thread(slug: 'meals', name: 'Meals'),
      ]);
      final h = await pumpApp(tester, llm: llm);
      await tester.enterText(search, 'chores');
      await tester.pumpAndSettle();
      llm.calls.clear();
      await tester.tap(inSidebar(control('Chores')));
      await tester.pumpAndSettle();
      expect(h.chat.activeThread, 'chores');
      expect(llm.calls.where((c) => c.startsWith('history')), [
        'history:chores',
      ]);
    });
  });

  group('the workspace menu', () {
    testWidgets('opens under the switcher with every workspace and action', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: planningServer());
      await tester.tap(switcher);
      await tester.pumpAndSettle();
      expect(h.shell.menuOpen, isTrue);
      for (final item in [
        'Q3 planning',
        'Household',
        'Files and settings',
        'Rename workspace',
        'Delete workspace…',
        'New workspace',
      ]) {
        expect(control(item), findsWidgets, reason: item);
      }
    });

    testWidgets('picking a workspace opens it and closes the menu', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: planningServer());
      await fromMenu(tester, 'Household');
      expect(h.chat.activeSlug, 'household');
      expect(h.shell.menuOpen, isFalse);
      expect(tester.widget<Tappable>(switcher).label, 'Workspaces: Household');
    });

    testWidgets('Esc and a tap outside close it', (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      await tester.tap(switcher);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.shell.menuOpen, isFalse);
      await tester.tap(switcher);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(700, 400));
      await tester.pumpAndSettle();
      expect(h.shell.menuOpen, isFalse);
    });

    testWidgets('names the keys that open each workspace on a desktop', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await pumpApp(tester, llm: planningServer());
      await tester.tap(switcher);
      await tester.pumpAndSettle();
      expect(find.text('Ctrl 1'), findsOneWidget);
      expect(find.text('Ctrl 2'), findsOneWidget);
      expect(find.text('Ctrl K'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('follows the saved arrangement', (tester) async {
      await pumpApp(
        tester,
        llm: planningServer(),
        prefsStore: FakePrefsStore(
          const Prefs(workspaceOrder: ['household', 'q3']),
        ),
      );
      await tester.tap(switcher);
      await tester.pumpAndSettle();
      expect(order(tester), ['Household', 'Q3 planning']);
    });

    testWidgets('dragging a workspace saves its new place', (tester) async {
      final store = FakePrefsStore();
      await pumpApp(tester, llm: planningServer(), prefsStore: store);
      await tester.tap(switcher);
      await tester.pumpAndSettle();
      expect(order(tester), ['Q3 planning', 'Household']);
      final from = tester.getCenter(control('Household').last);
      final gesture = await tester.startGesture(from);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(order(tester), ['Household', 'Q3 planning']);
      expect(store.saved.workspaceOrder, ['household', 'q3']);
    });
  });

  group('shortcuts', () {
    testWidgets('Ctrl+2 opens the second workspace', (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      await ctrl(tester, LogicalKeyboardKey.digit2);
      expect(h.chat.activeSlug, 'household');
      await ctrl(tester, LogicalKeyboardKey.digit1);
      expect(h.chat.activeSlug, 'q3');
    });
  });

  group('the Ctrl K switcher', () {
    final field = find.descendant(
      of: find.byType(QuickSwitcher),
      matching: find.byType(EditableText),
    );

    Finder row(String label) => find.descendant(
      of: find.byType(QuickSwitcher),
      matching: control(label),
    );

    testWidgets('opens over the window and Esc closes it', (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      expect(find.byType(QuickSwitcher), findsNothing);
      await ctrl(tester, LogicalKeyboardKey.keyK);
      expect(h.shell.switcherOpen, isTrue);
      expect(find.byType(QuickSwitcher), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.shell.switcherOpen, isFalse);
      expect(find.byType(QuickSwitcher), findsNothing);
    });

    testWidgets('Ctrl+K again closes it', (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      await ctrl(tester, LogicalKeyboardKey.keyK);
      await ctrl(tester, LogicalKeyboardKey.keyK);
      expect(h.shell.switcherOpen, isFalse);
    });

    testWidgets('lists each workspace with its chats when nothing is typed', (
      tester,
    ) async {
      await pumpApp(tester, llm: planningServer());
      await ctrl(tester, LogicalKeyboardKey.keyK);
      expect(row('Q3 planning'), findsOneWidget);
      expect(row('Household'), findsOneWidget);
    });

    testWidgets('a chat of another workspace opens that workspace', (
      tester,
    ) async {
      final llm = planningServer();
      llm.spaces[1].threads.add(const Thread(slug: 'chores', name: 'Chores'));
      llm.histories['chores'] = const [];
      const other = Thread(slug: 'chores', name: 'Chores');
      final h = await pumpApp(tester, llm: llm);
      expect(h.chat.activeSlug, 'q3');
      await ctrl(tester, LogicalKeyboardKey.keyK);
      await tester.enterText(field, other.name);
      await tester.pumpAndSettle();
      await tester.tap(row(other.name));
      await tester.pumpAndSettle();
      expect(h.chat.activeSlug, 'household');
      expect(h.chat.activeThread, other.slug);
      expect(h.shell.switcherOpen, isFalse);
    });

    testWidgets('Enter opens the first chat found', (tester) async {
      final h = await pumpApp(tester, llm: fourChats());
      await ctrl(tester, LogicalKeyboardKey.keyK);
      await tester.enterText(field, 'ff');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(h.shell.switcherOpen, isFalse);
      // Newest made first.
      expect(h.chat.activeThread, 'kickoff');
    });

    testWidgets('Down moves to the next, Up back', (tester) async {
      final h = await pumpApp(tester, llm: fourChats());
      await ctrl(tester, LogicalKeyboardKey.keyK);
      await tester.enterText(field, 'ff');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(h.chat.activeThread, 'offsite');
    });

    testWidgets('says when nothing matches', (tester) async {
      await pumpApp(tester, llm: planningServer());
      await ctrl(tester, LogicalKeyboardKey.keyK);
      await tester.enterText(field, 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches "zzzz".'), findsOneWidget);
    });

    testWidgets('a tap outside closes it', (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      await ctrl(tester, LogicalKeyboardKey.keyK);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(h.shell.switcherOpen, isFalse);
    });

    testWidgets('fits a phone', (tester) async {
      final h = await pumpApp(
        tester,
        llm: planningServer(),
        size: const Size(360, 640),
      );
      h.shell.toggleSwitcher();
      await tester.pumpAndSettle();
      expect(find.byType(QuickSwitcher), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the chat list', () {
    testWidgets('lists pinned chats, then recent ones, then the rest', (
      tester,
    ) async {
      await pumpApp(
        tester,
        llm: fourChats(),
        prefsStore: FakePrefsStore(
          Prefs(
            pinned: {
              Prefs.offKey(_server, 'q3'): const ['priorities'],
            },
            recent: {
              Prefs.offKey(_server, 'q3'): const ['budget'],
            },
          ),
        ),
      );
      // The newest chat opened at start, so it is the most recent.
      final rows = [
        'Pinned',
        'Quarter priorities',
        'Recent',
        'Kickoff agenda',
        'Budget questions',
        'All chats',
        'Offsite venues',
      ];
      for (final (a, b) in [
        for (var i = 1; i < rows.length; i++) (rows[i - 1], rows[i]),
      ]) {
        expect(top(tester, a), lessThan(top(tester, b)), reason: '$a, $b');
      }
      expect(find.text('on this device', findRichText: true), findsNothing);
      expect(
        find.textContaining('on this device', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a workspace never used here lists its chats alone', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: fourChats());
      // Opening one makes it recent; a new server has none yet.
      await h.prefs.forgetChat('q3', 'kickoff');
      await tester.pumpAndSettle();
      expect(inSidebar(find.text('Recent')), findsNothing);
      expect(inSidebar(find.text('All chats')), findsNothing);
      expect(inSidebar(control('Offsite venues')), findsOneWidget);
    });

    testWidgets('opening a chat puts it first in Recent', (tester) async {
      final store = FakePrefsStore();
      await pumpApp(tester, llm: fourChats(), prefsStore: store);
      await tester.tap(inSidebar(control('Offsite venues')));
      await tester.pumpAndSettle();
      expect(store.saved.recentIn(_server, 'q3').take(2), [
        'offsite',
        'kickoff',
      ]);
      expect(
        top(tester, 'Offsite venues'),
        lessThan(top(tester, 'Kickoff agenda')),
      );
    });

    testWidgets('the ⋯ menu pins and unpins the chat on screen', (
      tester,
    ) async {
      final store = FakePrefsStore();
      await pumpApp(tester, llm: planningServer(), prefsStore: store);
      await chatAction(tester, 'Pin chat');
      expect(store.saved.pinnedIn(_server, 'q3'), ['budget']);
      expect(inSidebar(find.text('Pinned')), findsOneWidget);
      expect(inSidebar(find.bySemanticsLabel('Pinned')), findsWidgets);
      await chatAction(tester, 'Unpin chat');
      expect(store.saved.pinnedIn(_server, 'q3'), isEmpty);
      expect(inSidebar(find.text('Pinned')), findsNothing);
    });

    testWidgets('a dot marks a chat whose answer ended elsewhere', (
      tester,
    ) async {
      final llm = planningServer()..hold = true;
      final h = await pumpApp(tester, llm: llm);
      await h.chat.send('And next quarter?');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(inSidebar(control('Quarter priorities')));
      await tester.pump(const Duration(milliseconds: 300));
      await llm.chat!.close();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        inSidebar(control('Budget questions, answer ready')),
        findsOneWidget,
      );
      await tester.tap(inSidebar(control('Budget questions, answer ready')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(inSidebar(control('Budget questions')), findsOneWidget);
    });

    testWidgets('New chat sits in the sidebar, not the header, when wide', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: planningServer());
      expect(control('New chat'), findsOneWidget);
      await tester.tap(control('New chat'));
      await tester.pumpAndSettle();
      expect(h.chat.activeThread, isNull);
    });
  });

  group('as drawn', () {
    testWidgets(
      'the logo tile has the launcher icon\'s colours in both themes',
      (tester) async {
        for (final theme in [ThemePref.light, ThemePref.dark]) {
          final prefs = FakePrefsStore(Prefs(theme: theme));
          await pumpApp(tester, llm: planningServer(), prefsStore: prefs);
          final tile = tester.widget<Container>(
            find
                .ancestor(
                  of: find.byType(RobinMark),
                  matching: find.byType(Container),
                )
                .first,
          );
          expect((tile.decoration! as BoxDecoration).color, iconGround);
          expect(
            tester.widget<RobinMark>(find.byType(RobinMark)).color,
            iconInk,
          );
        }
      },
    );

    testWidgets('the search is a borderless row 40 px tall', (tester) async {
      await pumpApp(tester, llm: planningServer());
      expect(inSidebar(find.byType(OutlineInputBorder)), findsNothing);
      final row = find
          .ancestor(of: search, matching: find.byType(AnimatedContainer))
          .first;
      expect(tester.getSize(row).height, 40);
    });

    testWidgets('Settings names the server it is connected to', (tester) async {
      await pumpApp(tester, llm: planningServer());
      expect(inSidebar(find.text('Connected to h')), findsOneWidget);
      expect(control('Settings, Connected to h'), findsOneWidget);
      expect(
        tester.widget<Tappable>(control('Settings, Connected to h')).tooltip,
        'https://h:3001',
      );
    });
  });
}
