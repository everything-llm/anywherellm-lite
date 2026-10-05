import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything/core/server_models.dart';
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
      expect(find.text('Workspaces'), findsWidgets);
      expect(find.text('Documents'), findsWidgets);
      expect(find.text('Upload'), findsWidgets);
      expect(find.text('Settings'), findsWidgets);
      expect(find.byTooltip('Menu'), findsNothing);
    });

    testWidgets('opens on the workspaces', (tester) async {
      final h = await pumpApp(tester);
      expect(h.nav.route, const WorkspacesRoute());
    });

    testWidgets('a sidebar entry opens its page', (tester) async {
      final h = await pumpApp(tester, connection: sampleConnection);
      await tester.tap(inSidebar('Documents'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const DocumentsRoute());
      await tester.tap(inSidebar('Upload'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const UploadRoute());
      await tester.tap(inSidebar('Settings'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const SettingsRoute());
      await tester.tap(inSidebar('Workspaces'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const WorkspacesRoute());
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
      await tester.tap(inSidebar('Upload'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const UploadRoute());
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
      for (final label in ['Workspaces', 'Documents', 'Upload', 'Settings']) {
        expect(tab(label), findsWidgets, reason: label);
      }
    });

    testWidgets('a tab opens its page', (tester) async {
      final h = await pumpApp(tester, size: size);
      await tester.tap(tab('Upload'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const UploadRoute());
    });

    testWidgets('the Settings tab opens Settings', (tester) async {
      final h = await pumpApp(tester, size: size);
      await tester.tap(tab('Settings'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const SettingsRoute());
    });
  });

  group('the Back button', () {
    testWidgets('steps from a document up to its list', (tester) async {
      final llm = FakeAnythingLlm()
        ..workspacesValue = [const Workspace(slug: 'a', name: 'A')];
      final h = await pumpApp(
        tester,
        llm: llm,
        connection: sampleConnection,
        size: const Size(400, 800),
        route: const WorkspaceRoute('a'),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.nav.route, const WorkspacesRoute());
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
      expect(h.nav.route, const WorkspacesRoute());
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
