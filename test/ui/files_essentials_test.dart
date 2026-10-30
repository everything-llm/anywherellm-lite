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
      expect((h.shell.rightOpen, h.shell.beside), (true, Beside.sources));
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

  testWidgets(
    'a row opens its details over the sheet, and Back gives it back',
    (tester) async {
      final h = await openPages(tester);
      await openPage(tester, 'Documents');
      expect(control('Remove Q3 roadmap.pdf from workspace'), findsNothing);
      await tester.tap(inSheet(control('Details of Q3 roadmap.pdf')));
      await tester.pumpAndSettle();
      expect(h.shell.document, 'Q3 roadmap.pdf.json');
      expect(find.text('Document details'), findsOneWidget);
      await tester.tap(control('Back to Documents'));
      await tester.pumpAndSettle();
      expect(h.shell.document, isNull);
      expect((h.shell.rightOpen, h.shell.pane), (true, Pane.files));
      expect(
        h.llm.calls.where((c) => c.startsWith('updateEmbeddings')),
        isEmpty,
      );
    },
  );

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
    // Save and Revert show only while the text has changed, in the header over the field.
    expect(inPages(control('Save')), findsNothing);
    expect(inPages(control('Revert')), findsNothing);
    final field = inPages(find.byType(TextField));
    await tester.enterText(field, 'Answer in German.');
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(inPages(control('Save'))).dy,
      lessThanOrEqualTo(tester.getTopLeft(field).dy),
    );
    await tester.tap(inPages(control('Revert')));
    await tester.pumpAndSettle();
    expect(find.text('Answer from the documents.'), findsOneWidget);
    expect(inPages(control('Save')), findsNothing);
    await tester.enterText(field, 'Answer in French.');
    await tester.pumpAndSettle();
    await tester.tap(inPages(control('Save')));
    await tester.pumpAndSettle();
    expect(llm.spaces.first.prompt, 'Answer in French.');
    expect(inPages(control('Save')), findsNothing);
    // The editor sets the prompt as code.
    final style = tester.widget<TextField>(field).style!;
    expect(style.fontFamily, 'JetBrains Mono');
    expect(style.fontSize, 15);
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
