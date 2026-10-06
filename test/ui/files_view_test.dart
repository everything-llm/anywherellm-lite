import 'dart:convert';

import 'package:anywherellm/ui/chat/chat_view.dart';
import 'package:anywherellm/ui/files/file_tree.dart';
import 'package:anywherellm/ui/files/files_view.dart';
import 'package:anywherellm/ui/sources/sources_panel.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
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
    expect(
      inPane(find.textContaining('chatMode is the workspace\'s chat mode')),
      findsOneWidget,
    );
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
      inPane(find.textContaining('AnywhereLLM never reads this')),
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

  testWidgets('a document\'s text downloads under its title', (tester) async {
    final h = await pumpApp(tester, llm: planningServer());
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await tapTree(tester, 'custom-documents');
    await tapTree(tester, 'Q3 roadmap.pdf');
    await tester.tap(inPane(control('Download text')));
    await tester.pumpAndSettle();
    expect(
      utf8.decode(h.saved['Q3 roadmap.pdf.txt']!),
      'The text of Q3 roadmap.pdf.',
    );
    expect(
      inPane(find.text('Saved to /saved/Q3 roadmap.pdf.txt')),
      findsOneWidget,
    );
  });

  testWidgets('a download that cannot be saved says why', (tester) async {
    final h = await pumpApp(tester, llm: planningServer());
    h.saveThrows = Exception('This device cannot save a file this way.');
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await tapTree(tester, 'custom-documents');
    await tapTree(tester, 'Q3 roadmap.pdf');
    await tester.tap(inPane(control('Download text')));
    await tester.pumpAndSettle();
    expect(h.saved, isEmpty);
    expect(find.text('Could not save Q3 roadmap.pdf'), findsOneWidget);
    expect(
      find.text('This device cannot save a file this way.'),
      findsOneWidget,
    );
  });

  testWidgets('chats export only once a place to save is chosen', (
    tester,
  ) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm);
    h.saveChosen = false;
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await tapTree(tester, 'settings');
    await tester.tap(inPane(control('JSON')));
    await tester.pumpAndSettle();
    expect(llm.calls, isNot(contains(startsWith('exportChats'))));
    h.saveChosen = true;
    await tester.tap(inPane(control('JSON')));
    await tester.pumpAndSettle();
    expect(
      String.fromCharCodes(h.saved['anythingllm-chats.json']!),
      llm.exported,
    );
    expect(
      inPane(find.text('Saved to /saved/anythingllm-chats.json')),
      findsOneWidget,
    );
  });

  testWidgets('deleting a folder asks first and names the workspaces', (
    tester,
  ) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm);
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await tapTree(tester, 'custom-documents');
    await tester.tap(inPane(control('Delete folder…')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        RegExp(
          r'^Delete the folder custom-documents and its \d+ documents\? They also leave Q3 planning\.$',
        ),
      ),
      findsOneWidget,
    );
    expect(llm.calls, isNot(contains('removeFolder:custom-documents')));
    await tester.tap(inPane(control('Delete')));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('removeFolder:custom-documents'));
    expect(inTree('custom-documents'), findsNothing);
  });
}
