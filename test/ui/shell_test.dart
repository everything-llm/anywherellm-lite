import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything/core/models.dart';
import 'package:everything/ui/sidebar.dart';
import 'package:everything/ui/state/nav_controller.dart';
import 'package:everything/ui/widgets/tappable.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// A sidebar entry by its label; the pages have headings of their own with the same words.
Finder inSidebar(String label) =>
    find.descendant(of: find.byType(Sidebar), matching: find.text(label));

/// A tab of the bottom bar. Only on a phone is the sidebar not mounted, so the labels are unique.
Finder tab(String label) => find.byWidgetPredicate(
  (widget) => widget is Tappable && widget.label == label,
);

void main() {
  group('a wide window', () {
    testWidgets('shows the sidebar beside the page', (tester) async {
      await pumpApp(tester);
      expect(find.byType(Sidebar), findsOneWidget);
      expect(find.text('Research'), findsWidgets);
      expect(find.text('Skills'), findsWidgets);
      expect(find.text('Inbox'), findsWidgets);
      expect(find.byTooltip('Menu'), findsNothing);
    });

    testWidgets('opens on the overview', (tester) async {
      final h = await pumpApp(tester);
      expect(h.nav.route, const OverviewRoute());
    });

    testWidgets('a sidebar entry opens its page', (tester) async {
      final h = await pumpApp(tester);
      await tester.tap(inSidebar('Skills'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const SkillsListRoute());
      await tester.tap(inSidebar('Inbox'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const InboxRoute());
      await tester.tap(inSidebar('Research'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const ResearchListRoute());
      await tester.tap(inSidebar('Overview'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const OverviewRoute());
    });

    testWidgets('a library with findings shows a badge that counts them', (
      tester,
    ) async {
      final api = FakeApi()
        ..overviewValue = sampleOverview(
          findings: const [
            Finding(
              library: 'research',
              path: 'a.md',
              message: 'm',
              severity: 'error',
            ),
            Finding(
              library: 'research',
              path: 'b.md',
              message: 'm',
              severity: 'warning',
            ),
            Finding(
              library: 'skills',
              path: 'c',
              message: 'm',
              severity: 'warning',
            ),
          ],
        );
      await pumpApp(tester, api: api);
      final research = find.ancestor(
        of: inSidebar('Research'),
        matching: find.byType(NavItem),
      );
      expect(
        find.descendant(of: research, matching: find.text('2')),
        findsOneWidget,
      );
      expect(find.byTooltip('2 things to look at'), findsOneWidget);
      expect(find.byTooltip('1 thing to look at'), findsOneWidget);
    });

    testWidgets('a clean library has no badge', (tester) async {
      await pumpApp(tester);
      expect(find.textContaining('to look at'), findsNothing);
    });
  });

  group('a tablet window', () {
    const size = Size(780, 800);

    testWidgets('has a top bar and no inline sidebar', (tester) async {
      await pumpApp(tester, size: size);
      expect(find.byTooltip('Menu'), findsOneWidget);
      expect(tester.getTopLeft(find.byType(Sidebar)).dx, lessThan(0));
    });

    testWidgets(
      'the menu opens the sidebar as a drawer and a tap outside closes it',
      (tester) async {
        final h = await pumpApp(tester, size: size);
        await tester.tap(find.byTooltip('Menu'));
        await tester.pumpAndSettle();
        expect(h.shell.sideOpen, isTrue);
        expect(tester.getTopLeft(find.byType(Sidebar)).dx, 0);

        await tester.tapAt(const Offset(700, 400));
        await tester.pumpAndSettle();
        expect(h.shell.sideOpen, isFalse);
        expect(tester.getTopLeft(find.byType(Sidebar)).dx, lessThan(0));
      },
    );

    testWidgets('Escape closes the drawer', (tester) async {
      final h = await pumpApp(tester, size: size);
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.shell.sideOpen, isFalse);
    });

    testWidgets('choosing a page closes the drawer', (tester) async {
      final h = await pumpApp(tester, size: size);
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(inSidebar('Inbox'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const InboxRoute());
      expect(h.shell.sideOpen, isFalse);
    });
  });

  group('a phone window', () {
    const size = Size(500, 800);

    testWidgets('has a tab bar with four tabs and no top bar menu', (
      tester,
    ) async {
      await pumpApp(tester, size: size);
      expect(find.byTooltip('Menu'), findsNothing);
      for (final label in ['Overview', 'Research', 'Skills', 'Inbox']) {
        expect(tab(label), findsWidgets, reason: label);
      }
    });

    testWidgets('a tab opens its page', (tester) async {
      final h = await pumpApp(tester, size: size);
      await tester.tap(tab('Inbox'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const InboxRoute());
    });
  });

  group('the Back button', () {
    testWidgets('steps from a document up to its list', (tester) async {
      final api = FakeApi()
        ..researchDocs = {'a.md': const ResearchDoc(path: 'a.md', text: 'RAW')};
      final h = await pumpApp(
        tester,
        api: api,
        size: const Size(400, 800),
        route: const ResearchDocRoute('a.md'),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.nav.route, const ResearchListRoute());
    });

    testWidgets('closes an open drawer before it does anything else', (
      tester,
    ) async {
      final h = await pumpApp(tester, size: const Size(760, 800));
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(h.shell.sideOpen, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.shell.sideOpen, isFalse);
      expect(h.nav.route, const OverviewRoute());
    });
  });

  group('the tabs', () {
    testWidgets('grow with a very large font instead of overflowing', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      // An overflow would fail the test as an uncaught exception.
      await pumpApp(tester, size: const Size(360, 800));
    });
  });
}
