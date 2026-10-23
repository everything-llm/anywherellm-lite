import 'package:anywherellm/core/browser_tabs.dart';
import 'package:anywherellm/core/page_status.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/core/skill_pages.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:anywherellm/ui/chat/tabs_sheet.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_toolkit.dart';
import '../support/pump.dart';

const _budgetTab = '/browser-lean/aaaaaaaaaaaaaaaaaaaaaaaa.html';
const _webTab = '/browser-lean/bbbbbbbbbbbbbbbbbbbbbbbb.html';
const _homeTab = '/browser-lean/cccccccccccccccccccccccc.html';
const _library = '/library-lean/q9Zx_-1aB2.html';
const _manager = '/apps-lean/manager-q9Zx_-1aB2c3D4e5F6g7H8i9.html';

/// A time [minutes] and [seconds] from now.
DateTime _in(int minutes, [int seconds = 0]) =>
    DateTime.now().toUtc().add(Duration(minutes: minutes, seconds: seconds));

/// The planning server, its budget chat's answer ending with a card for [_budgetTab].
FakeAnythingLlm _server() {
  final llm = planningServer();
  llm.histories['budget'] = [
    ...llm.histories['budget']!,
    const ChatMessage(role: Role.user, text: 'Find the supplier prices.'),
    const ChatMessage(
      role: Role.assistant,
      text:
          '[![Prices](/browser-lean/aaaaaaaaaaaaaaaaaaaaaaaa-card.jpg)]'
          '($_budgetTab)\n\n**Prices** · supplier.example.com',
    ),
  ];
  llm.tabStates
    ..[_budgetTab] = const TabState(
      title: 'Prices',
      host: 'supplier.example.com',
    )
    ..[_webTab] = const TabState(
      title: 'Opening hours',
      host: 'library.example.org',
      mine: true,
    )
    ..[_homeTab] = const TabState(title: 'Heating', host: 'heat.example.com');
  return llm;
}

FakeToolkit _toolkit({List<OpenTab>? tabs}) => FakeToolkit()
  ..served = {ToolkitFeature.pages}
  ..skillPages = const {
    SkillPage.appsManager: _manager,
    SkillPage.library: _library,
  }
  ..tabs = tabs;

List<OpenTab> _tabs() => [
  OpenTab(path: _budgetTab, workspace: 'q3', until: _in(14, 10)),
  OpenTab(path: _webTab, workspace: 'q3', until: _in(14, 10)),
  OpenTab(path: _homeTab, workspace: 'household', until: _in(2, 50)),
];

Future<Harness> _open(
  WidgetTester tester,
  FakeToolkit toolkit, {
  FakeAnythingLlm? llm,
}) => pumpApp(
  tester,
  llm: llm ?? _server(),
  toolkitServer: toolkit,
  shelf: true,
  canViewApps: true,
);

void main() {
  testWidgets('the Browser row says how many tabs and when the first closes', (
    tester,
  ) async {
    await _open(tester, _toolkit(tabs: _tabs()));
    expect(find.text('Browser'), findsOneWidget);
    expect(find.text('3 tabs open · first closes in 3 min'), findsOneWidget);
  });

  testWidgets('a bridge that lists no tabs shows no Browser row', (
    tester,
  ) async {
    await _open(tester, _toolkit());
    expect(find.text('Apps'), findsOneWidget);
    expect(find.text('Browser'), findsNothing);
  });

  testWidgets('with every tab closed it says so, and a past until is closed', (
    tester,
  ) async {
    await _open(
      tester,
      _toolkit(
        tabs: [OpenTab(path: _homeTab, workspace: 'household', until: _in(-2))],
      ),
    );
    expect(find.text('No tabs open'), findsOneWidget);
  });

  testWidgets('the rows say what changed and what failed since last seen', (
    tester,
  ) async {
    final toolkit = _toolkit()
      ..status = PageStatus(
        changed: [_in(-1), _in(-2), _in(-3)],
        failed: [_in(-5)],
      );
    final h = await _open(tester, toolkit);
    expect(find.text('3 changed today'), findsOneWidget);
    expect(find.text('1 run failed'), findsOneWidget);
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(h.prefs.librarySeen, isNotNull);
    h.shell.openShelf();
    await tester.pumpAndSettle();
    expect(find.text('1 run failed'), findsNothing);
    expect(find.text('Toolkits and runs'), findsOneWidget);
  });

  testWidgets(
    'the sheet groups the tabs by workspace, soonest to close first',
    (tester) async {
      final h = await _open(tester, _toolkit(tabs: _tabs()));
      await tester.tap(find.text('Browser'));
      await tester.pumpAndSettle();
      expect(h.shell.popup.value, Popup.browserTabs);
      expect(h.shell.shelfOpen, isFalse);
      expect(find.byType(TabsSheet), findsOneWidget);
      expect(find.text('3 tabs open · soonest to close first'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Household')).dy,
        lessThan(tester.getTopLeft(find.text('Q3 planning')).dy),
      );
      expect(find.text('Closes in 3 min'), findsOneWidget);
      expect(find.text('Closes in 15 min'), findsOneWidget);
      // A chat read here names its tab; another tab is named by its page.
      expect(
        find.descendant(
          of: find.byType(TabsSheet),
          matching: find.text('Budget questions'),
        ),
        findsOneWidget,
      );
      expect(find.text('Opening hours'), findsOneWidget);
      expect(find.textContaining('You have it'), findsOneWidget);
      expect(find.textContaining('Agent has it'), findsNWidgets(2));
    },
  );

  testWidgets('a tab whose state says closed is left out of the sheet', (
    tester,
  ) async {
    final llm = _server();
    llm.tabStates[_webTab] = const TabState(closed: true);
    await _open(tester, _toolkit(tabs: _tabs()), llm: llm);
    await tester.tap(find.text('Browser'));
    await tester.pumpAndSettle();
    expect(find.text('Opening hours'), findsNothing);
    expect(find.text('2 tabs open · soonest to close first'), findsOneWidget);
  });

  testWidgets('a chat\'s tab opens over that chat with the bar', (
    tester,
  ) async {
    final h = await _open(tester, _toolkit(tabs: _tabs()));
    await h.chat.select('household');
    await tester.pumpAndSettle();
    h.shell.togglePopup(Popup.browserTabs);
    await tester.pumpAndSettle();
    // The budget chat was read, so it names its tab.
    await tester.tap(
      find.descendant(
        of: find.byType(TabsSheet),
        matching: find.text('Budget questions'),
      ),
    );
    await tester.pumpAndSettle();
    final open = h.shell.popup.value as BrowserOpen;
    expect(open.tab, Uri.parse('https://h:3001$_budgetTab'));
    expect(open.inChat, isTrue);
    expect(h.chat.activeSlug, 'q3');
    expect(h.chat.activeThread, 'budget');
  });

  testWidgets('a tab of no chat read here opens without the bar', (
    tester,
  ) async {
    final h = await _open(tester, _toolkit(tabs: _tabs()));
    await tester.tap(find.text('Browser'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heating'));
    await tester.pumpAndSettle();
    final open = h.shell.popup.value as BrowserOpen;
    expect(open.tab, Uri.parse('https://h:3001$_homeTab'));
    expect(open.inChat, isFalse);
    expect(find.text('Message the agent…'), findsNothing);
    expect(h.appView!.channel, isNull);
  });

  testWidgets('the footnote links the Vault only while it is set up', (
    tester,
  ) async {
    final toolkit = _toolkit(tabs: _tabs());
    final h = await _open(tester, toolkit);
    h.shell
      ..closeShelf()
      ..togglePopup(Popup.browserTabs);
    await tester.pumpAndSettle();
    expect(find.text('Vault'), findsNothing);
    h.shell.closePopup();
    toolkit.skillPages = {
      ...toolkit.skillPages,
      SkillPage.vault: '/vault-lean/aB3_-x9.html',
    };
    await h.toolkit.readPages();
    h.shell.togglePopup(Popup.browserTabs);
    await tester.pumpAndSettle();
    await tester.tap(control('Vault'));
    await tester.pumpAndSettle();
    expect(
      (h.shell.popup.value as PageOpen).url.path,
      '/vault-lean/aB3_-x9.html',
    );
  });
}
