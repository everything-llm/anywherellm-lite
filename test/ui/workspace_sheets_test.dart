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
    final h = await pumpApp(tester, llm: llm, onChat: false);
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
    await pumpApp(tester, llm: planningServer(), onChat: false);
    await tester.tap(find.byTooltip('Workspace settings').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename').first);
    await tester.pumpAndSettle();
    expect(_fields, findsOneWidget);
    expect(_inSheet(find.text('Instructions')), findsNothing);
  });
}
