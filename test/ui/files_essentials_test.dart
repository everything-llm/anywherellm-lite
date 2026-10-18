import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/core/files.dart';
import 'package:anywherellm/core/upload.dart';
import 'package:anywherellm/ui/files/workspace_pages.dart';
import 'package:anywherellm/ui/sources/sources_panel.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/widgets/upload_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

Finder inPages(Finder finder) =>
    find.descendant(of: find.byType(WorkspacePages), matching: finder);

/// [finder] in the Documents sheet.
Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(SourcesPanel), matching: finder);

/// Opens the open workspace's pages, the window tall enough to show each whole.
Future<Harness> openPages(WidgetTester tester, {FakeAnythingLlm? llm}) async {
  final h = await pumpApp(
    tester,
    llm: llm ?? planningServer(),
    size: const Size(390, 1400),
  );
  h.shell.showPane(Pane.files);
  await tester.pumpAndSettle();
  return h;
}

/// Opens the page named [title] from the workspace's overview.
Future<void> openPage(WidgetTester tester, String title) async {
  await tester.tap(inPages(find.text(title)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the pages are the workspace\'s, and Back steps out', (
    tester,
  ) async {
    final h = await openPages(tester);
    expect(inPages(find.text('Workspace')), findsOneWidget);
    expect(inPages(find.text('Q3 planning')), findsOneWidget);
    expect(inPages(find.text('2 chats')), findsOneWidget);
    expect(
      inPages(find.text('2 documents, 2 used in answers')),
      findsOneWidget,
    );
    expect(inPages(find.text('2 of 2 used in answers')), findsOneWidget);
    await openPage(tester, 'Answer from');
    expect(h.shell.workspacePage, FilesSection.answers);
    // Three settings only, in the composer's words.
    expect(inPages(find.text('Files & knowledge')), findsOneWidget);
    expect(inPages(find.text('Chat model')), findsOneWidget);
    expect(inPages(find.text('Chat history')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.shell.workspacePage, isNull);
    expect(h.shell.pane, Pane.files);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.shell.pane, Pane.chats);
  });

  testWidgets(
    'Documents opens the sheet, and one switched off is off in answers',
    (tester) async {
      final h = await openPages(tester);
      await openPage(tester, 'Documents');
      expect(h.shell.sourcesOpen, isTrue);
      expect(inSheet(find.text('120 words')), findsNWidgets(2));
      for (final label in ['Add a file', 'Add a link', 'Paste text']) {
        expect(inSheet(control(label)), findsOneWidget, reason: label);
      }
      await tester.tap(inSheet(control('Use Q3 roadmap.pdf in answers')));
      await tester.pumpAndSettle();
      expect(h.sources.onCount, 1);
      expect(inSheet(find.text('Not used · 120 words')), findsOneWidget);
      h.shell.closeSources();
      await tester.pumpAndSettle();
      expect(inPages(find.text('1 of 2 used in answers')), findsOneWidget);
    },
  );

  testWidgets('a document opens its text, with Download and Remove', (
    tester,
  ) async {
    final h = await openPages(tester);
    await openPage(tester, 'Documents');
    await tester.tap(control('View extracted text of Q3 roadmap.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('The text of Q3 roadmap.pdf.'), findsOneWidget);
    expect(find.text('Used in answers'), findsOneWidget);
    await tester.tap(control('Download the extracted text'));
    await tester.pumpAndSettle();
    expect(h.saved.keys, contains('Q3 roadmap.pdf.txt'));
    await tapVisible(tester, control('Remove from workspace'));
    await tester.pumpAndSettle();
    expect(h.files.reading, isNull);
    // The sheet the text was opened from comes back, with the undo.
    expect(h.shell.sourcesOpen, isTrue);
    expect(inSheet(find.text('Removed Q3 roadmap.pdf')), findsOneWidget);
    expect(
      h.sources.files.where((f) => f.on).map((f) => f.title),
      isNot(contains('Q3 roadmap.pdf')),
    );
    // The undo for the removal lets go.
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('a document whose text the server left out says so', (
    tester,
  ) async {
    final llm = planningServer()
      ..textless.add('custom-documents/Q3 roadmap.pdf.json');
    final h = await openPages(tester, llm: llm);
    await openPage(tester, 'Documents');
    await tester.tap(control('View extracted text of Q3 roadmap.pdf'));
    await tester.pumpAndSettle();
    expect(
      find.text('The server sent no text for this document.'),
      findsOneWidget,
    );
    await tester.tap(control('Download the extracted text'));
    await tester.pumpAndSettle();
    expect(h.saved, isEmpty);
    expect(h.sources.problems.single.title, 'Could not save Q3 roadmap.pdf');
  });

  testWidgets('a text that cannot be read says why', (tester) async {
    final llm = planningServer()
      ..errors['document'] = const ApiException('The server is down.');
    await openPages(tester, llm: llm);
    await openPage(tester, 'Documents');
    await tester.tap(control('View extracted text of Q3 roadmap.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('Could not read Q3 roadmap.pdf'), findsOneWidget);
    expect(find.text('The server is down.'), findsOneWidget);
  });

  testWidgets('a file added waits, then goes to the workspace', (tester) async {
    final llm = planningServer();
    await openPages(tester, llm: llm);
    await openPage(tester, 'Documents');
    final queue = tester.widget<UploadQueue>(inSheet(find.byType(UploadQueue)));
    await queue.onSend([
      UploadFile(name: 'a.md', read: () async => [1]),
    ]);
    await tester.pumpAndSettle();
    expect(llm.calls, contains('upload:a.md'));
    expect(llm.spaces.first.docs, hasLength(3));
  });

  testWidgets('Test a question opens under the adders and Done closes it', (
    tester,
  ) async {
    await openPages(tester);
    await openPage(tester, 'Documents');
    await tapVisible(tester, inSheet(control('Test a question')));
    await tester.pumpAndSettle();
    expect(inSheet(control('Test a question')), findsNothing);
    expect(inSheet(control('Done')), findsOneWidget);
    await tapVisible(tester, inSheet(control('Done')));
    await tester.pumpAndSettle();
    expect(inSheet(control('Test a question')), findsOneWidget);
  });

  testWidgets('Instructions is the workspace\'s PROMPT.md', (tester) async {
    final llm = planningServer()
      ..spaces[0].prompt = 'Answer from the documents.';
    final h = await openPages(tester, llm: llm);
    await openPage(tester, 'Instructions');
    expect(h.files.section, FilesSection.instructions);
    // Save shows once the text has changed.
    expect(inPages(control('Save')), findsNothing);
    await tester.enterText(
      inPages(find.byType(TextField)),
      'Answer in French.',
    );
    // Save slides in under the field.
    await tester.pumpAndSettle();
    await tester.tap(inPages(control('Save')));
    await tester.pumpAndSettle();
    expect(llm.spaces.first.prompt, 'Answer in French.');
  });

  testWidgets('Answer from changes the mode as the composer names it', (
    tester,
  ) async {
    final llm = planningServer();
    await openPages(tester, llm: llm);
    await openPage(tester, 'Answer from');
    for (final label in [
      'Files, knowledge & tools',
      'Files & knowledge',
      'Files only',
    ]) {
      expect(inPages(find.text(label)), findsOneWidget, reason: label);
    }
    await tester.tap(inPages(find.text('Files only')));
    await tester.pump();
    await tester.tap(inPages(control('Save')));
    await tester.pumpAndSettle();
    expect(llm.spaces.first.settings['chatMode'], 'query');
  });

  testWidgets('a page follows another workspace opened meanwhile', (
    tester,
  ) async {
    final h = await openPages(tester);
    await openPage(tester, 'Instructions');
    await h.chat.select('household');
    await tester.pumpAndSettle();
    expect(h.files.workspace, 'household');
  });
}
