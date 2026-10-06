import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/ui/sidebar.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
import '../support/pump.dart';

Finder control(String label) => find.byWidgetPredicate(
  (widget) => widget is Tappable && widget.label == label,
);

Finder inSidebar(Finder finder) =>
    find.descendant(of: find.byType(Sidebar), matching: finder);

Finder get search => find.bySemanticsLabel('Search workspaces and chats');

/// The workspace names in the sidebar, top to bottom.
List<String> order(WidgetTester tester) {
  final rows = [
    for (final name in ['Q3 planning', 'Household'])
      (name, tester.getTopLeft(inSidebar(control(name)).first).dy),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final (name, _) in rows) name];
}

void main() {
  group('search', () {
    testWidgets('keeps the workspaces and chats that match', (tester) async {
      await pumpApp(tester, llm: planningServer());
      expect(inSidebar(control('Household')), findsOneWidget);
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
      await pumpApp(tester, llm: planningServer());
      await tester.enterText(search, 'HOUSE');
      await tester.pumpAndSettle();
      expect(inSidebar(control('Household')), findsOneWidget);
      expect(inSidebar(control('Q3 planning')), findsNothing);
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
      expect(inSidebar(control('Household')), findsOneWidget);
      expect(inSidebar(control('Budget questions')), findsOneWidget);
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

  group('order', () {
    testWidgets('follows the saved arrangement', (tester) async {
      await pumpApp(
        tester,
        llm: planningServer(),
        prefsStore: FakePrefsStore(
          const Prefs(workspaceOrder: ['household', 'q3']),
        ),
      );
      expect(order(tester), ['Household', 'Q3 planning']);
    });

    testWidgets('dragging a workspace saves its new place', (tester) async {
      final store = FakePrefsStore();
      await pumpApp(tester, llm: planningServer(), prefsStore: store);
      expect(order(tester), ['Q3 planning', 'Household']);
      final from = tester.getCenter(inSidebar(control('Household')).first);
      final gesture = await tester.startGesture(from);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, -200));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -100));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(order(tester), ['Household', 'Q3 planning']);
      expect(store.saved.workspaceOrder, ['household', 'q3']);
    });

    testWidgets('no drag while searching', (tester) async {
      final store = FakePrefsStore();
      await pumpApp(tester, llm: planningServer(), prefsStore: store);
      await tester.enterText(search, 'o');
      await tester.pumpAndSettle();
      final from = tester.getCenter(inSidebar(control('Household')).first);
      final gesture = await tester.startGesture(from);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, -300));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.saved.workspaceOrder, isEmpty);
    });
  });
}
