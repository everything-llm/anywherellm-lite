import 'package:flutter/material.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/widgets/sheet.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:anywherellm/ui/workspace_sheets.dart';
import 'package:anywherellm/ui/workspace_switcher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// Opens New workspace from the Workspaces sheet on the Chats tab.
Future<void> _openNew(WidgetTester tester) async {
  await tester.tap(find.byType(WorkspaceSwitcher));
  await tester.pumpAndSettle();
  await tester.tap(find.text('New workspace'));
  await tester.pumpAndSettle();
}

/// What [finder] finds inside the sheet.
Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(WorkspaceSheetView), matching: finder);

/// The sheet's fields, the name first.
Finder get _fields => typingField(find.byType(WorkspaceSheetView));

void main() {
  testWidgets('a new workspace is made with its instructions', (tester) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm, shelf: true);
    await _openNew(tester);
    expect(_inSheet(find.text('Instructions')), findsOneWidget);
    await tester.enterText(_fields.at(0), 'Recipes');
    await tester.enterText(_fields.at(1), 'Answer as a chef.');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(h.chat.active!.name, 'Recipes');
    expect(llm.spaces.last.prompt, 'Answer as a chef.');
  });

  testWidgets('Rename workspace asks only for the name', (tester) async {
    await pumpApp(tester, llm: planningServer(), shelf: true);
    await tester.tap(find.byTooltip('Workspace settings').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename').first);
    await tester.pumpAndSettle();
    expect(_fields, findsOneWidget);
    expect(_inSheet(find.text('Instructions')), findsNothing);
  });

  testWidgets('Create waits for a name instead of closing on nothing', (
    tester,
  ) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm, shelf: true);
    final before = h.chat.workspaces.length;
    await _openNew(tester);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    // Still open, and nothing made.
    expect(find.byType(WorkspaceSheetView), findsOneWidget);
    expect(h.chat.workspaces.length, before);
    await tester.enterText(_fields.at(0), 'Recipes');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceSheetView), findsNothing);
    expect(h.chat.active!.name, 'Recipes');
  });

  testWidgets('a sheet covers the system bars and keeps its words clear', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.resetPadding);
    await pumpApp(
      tester,
      llm: planningServer(),
      size: const Size(360, 640),
      shelf: true,
    );
    await _openNew(tester);
    // The scrim and the sheet's ground reach the window's edges...
    expect(
      tester.getRect(find.byType(SheetFrame)),
      const Rect.fromLTWH(0, 0, 360, 640),
    );
    // ...and the title and the button stay between the bars.
    expect(
      tester.getTopLeft(find.text('New workspace').last).dy,
      greaterThanOrEqualTo(24),
    );
    expect(
      tester.getBottomLeft(find.text('Create')).dy,
      lessThanOrEqualTo(640 - 24),
    );
  });

  testWidgets('Reorder moves a workspace up or down, then Done goes back', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer(), shelf: true);
    await tester.tap(find.byType(WorkspaceSwitcher));
    await tester.pumpAndSettle();
    await tester.tap(control('Reorder'));
    await tester.pumpAndSettle();
    expect(find.text('Reorder workspaces'), findsOneWidget);
    expect(
      find.text(
        'Move a workspace up or down. You can also press and hold a row, then drag it.',
      ),
      findsOneWidget,
    );
    bool on(String label) =>
        tester.widget<Tappable>(control(label)).onTap != null;
    // The first can go only down, the last only up.
    expect(on('Move Q3 planning up'), isFalse);
    expect(on('Move Q3 planning down'), isTrue);
    expect(on('Move Household up'), isTrue);
    expect(on('Move Household down'), isFalse);

    await tester.tap(control('Move Q3 planning down'));
    await tester.pumpAndSettle();
    expect(h.chat.orderedWorkspaces.map((w) => w.slug), ['household', 'q3']);
    expect(on('Move Household up'), isFalse);
    await tester.tap(control('Move Q3 planning up'));
    await tester.pumpAndSettle();
    expect(h.chat.orderedWorkspaces.map((w) => w.slug), ['q3', 'household']);

    await tester.tap(control('Done'));
    await tester.pumpAndSettle();
    expect(h.shell.popup.value, Popup.workspaces);
    expect(find.text('Reorder workspaces'), findsNothing);
  });

  testWidgets('one workspace has nothing to reorder', (tester) async {
    final llm = planningServer()..spaces.removeLast();
    await pumpApp(tester, llm: llm, shelf: true);
    await tester.tap(find.byType(WorkspaceSwitcher));
    await tester.pumpAndSettle();
    expect(find.text('Workspaces'), findsWidgets);
    expect(control('Reorder'), findsNothing);
  });
}
