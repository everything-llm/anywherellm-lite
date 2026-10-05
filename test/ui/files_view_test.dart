import 'package:everything/ui/chat/chat_view.dart';
import 'package:everything/ui/files/file_tree.dart';
import 'package:everything/ui/files/files_view.dart';
import 'package:everything/ui/sources/sources_panel.dart';
import 'package:everything/ui/state/shell_controller.dart';
import 'package:everything/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

Finder control(String label) => find.byWidgetPredicate(
  (widget) => widget is Tappable && widget.label == label,
);

Finder inTree(String label) =>
    find.descendant(of: find.byType(FileTree), matching: control(label));

Finder inPane(Finder finder) =>
    find.descendant(of: find.byType(FilesView), matching: finder);

Future<void> tapTree(WidgetTester tester, String label) async {
  await tester.tap(inTree(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Files replaces the chat and Sources, and Chats brings them back',
    (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      await tester.tap(control('Files'));
      await tester.pumpAndSettle();
      expect(h.shell.pane, Pane.files);
      expect(find.byType(FileTree), findsOneWidget);
      expect(find.byType(SourcesPanel).hitTestable(), findsNothing);
      expect(find.byType(ChatView).hitTestable(), findsNothing);
      expect(inTree('Q3 planning'), findsOneWidget);
      expect(inTree('custom-documents'), findsOneWidget);
      await tester.tap(control('Chats'));
      await tester.pumpAndSettle();
      expect(find.byType(FileTree), findsNothing);
      expect(find.text('About 40k.'), findsOneWidget);
    },
  );

  testWidgets('a workspace prompt is edited and saved', (tester) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm);
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await tapTree(tester, 'Q3 planning');
    await tapTree(tester, 'PROMPT.md');
    expect(
      inPane(find.text('Empty: the server\'s default system prompt applies.')),
      findsOneWidget,
    );
    await tester.enterText(inPane(find.byType(TextField)), 'Answer in French.');
    await tester.pump();
    await tester.tap(inPane(control('Save')));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('updateWorkspace:q3'));
    expect(llm.spaces.first.prompt, 'Answer in French.');
    expect(
      inPane(
        find.text(
          'This prompt replaces the default system prompt in this workspace.',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('bad settings show why and keep the draft', (tester) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm);
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await tapTree(tester, 'Q3 planning');
    await tapTree(tester, 'settings.json');
    await tester.enterText(inPane(find.byType(TextField)), '{"topN": 0}');
    await tester.pump();
    await tester.tap(inPane(control('Save')));
    await tester.pumpAndSettle();
    expect(find.text('Could not save settings.json'), findsOneWidget);
    expect(find.text('{"topN": 0}'), findsOneWidget);
    expect(llm.calls, isNot(contains('updateWorkspace:q3')));
  });

  testWidgets('a chat shows read only, and a secret shows locked', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer());
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await tapTree(tester, 'Q3 planning');
    await tapTree(tester, 'chats');
    await tapTree(tester, 'Budget questions.md');
    expect(inPane(find.text('Read only')), findsOneWidget);
    expect(inPane(find.textContaining('About 40k.')), findsOneWidget);
    await tapTree(tester, '.env');
    expect(
      inPane(find.textContaining('Nilson never reads this')),
      findsOneWidget,
    );
  });

  testWidgets('deleting from the library asks first and names the workspaces', (
    tester,
  ) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm);
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await tapTree(tester, 'custom-documents');
    await tapTree(tester, 'Q3 roadmap.pdf');
    expect(inPane(find.text('Used by Q3 planning.')), findsOneWidget);
    await tester.tap(inPane(control('Delete…')));
    await tester.pumpAndSettle();
    expect(
      find.text('Delete Q3 roadmap.pdf from the library and from 1 workspace?'),
      findsOneWidget,
    );
    expect(llm.calls, isNot(contains(startsWith('removeDocuments'))));
    await tester.tap(inPane(control('Delete')));
    await tester.pumpAndSettle();
    expect(
      llm.library.keys,
      isNot(contains(startsWith('custom-documents/Q3'))),
    );
    expect(inTree('Q3 roadmap.pdf'), findsNothing);
  });
}
