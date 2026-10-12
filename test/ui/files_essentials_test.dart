import 'dart:convert';

import 'package:anywherellm/core/files.dart';
import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/core/upload.dart';
import 'package:anywherellm/ui/files/essentials.dart';
import 'package:anywherellm/ui/files/file_tree.dart';
import 'package:anywherellm/ui/files/files_view.dart';
import 'package:anywherellm/ui/files/workspace_pages.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/widgets/upload_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

Finder inSidebar(Finder finder) =>
    find.descendant(of: find.byType(FileTree), matching: finder);

Finder inPane(Finder finder) =>
    find.descendant(of: find.byType(FilesView), matching: finder);

/// The title in the Files pane's header.
String paneTitle(WidgetTester tester) =>
    tester.widgetList<Text>(inPane(find.byType(Text))).first.data!;

Future<Harness> openFiles(
  WidgetTester tester, {
  FakeAnythingLlm? llm,
  Size size = const Size(1280, 1800),
}) async {
  final h = await pumpApp(tester, llm: llm ?? planningServer(), size: size);
  h.shell.showPane(Pane.files);
  await tester.pumpAndSettle();
  return h;
}

Future<void> tapSection(WidgetTester tester, String label) async {
  await tester.tap(inSidebar(control(label)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Files opens on Essentials, on the open workspace\'s documents', (
    tester,
  ) async {
    final h = await openFiles(tester);
    expect(h.files.essentials, isTrue);
    for (final label in [
      'Documents, 2 on',
      'Instructions',
      'Answer settings',
    ]) {
      expect(inSidebar(control(label)), findsOneWidget, reason: label);
    }
    expect(paneTitle(tester), 'Documents');
    expect(inPane(find.text('2 documents, 2 used in answers')), findsOneWidget);
    expect(inPane(find.text('Q3 roadmap.pdf')), findsOneWidget);
    expect(inPane(find.text('120 words')), findsNWidgets(2));
    for (final label in ['Add a file', 'Add a link', 'Paste text']) {
      expect(inPane(control(label)), findsOneWidget, reason: label);
    }
    expect(
      inPane(control('View extracted text of Q3 roadmap.pdf')),
      findsOneWidget,
    );
  });

  testWidgets('a document switched off here is off beside the chat too', (
    tester,
  ) async {
    final h = await openFiles(tester);
    await tester.tap(inPane(control('Use Q3 roadmap.pdf in answers')));
    await tester.pumpAndSettle();
    expect(h.sources.onCount, 1);
    expect(inSidebar(control('Documents, 1 on')), findsOneWidget);
    expect(
      inPane(find.text('120 words · Not used in answers')),
      findsOneWidget,
    );
    expect(inPane(find.text('2 documents, 1 used in answers')), findsOneWidget);
  });

  testWidgets('a pinned document says so', (tester) async {
    final llm = planningServer();
    await llm.pinDocument(
      'q3',
      'custom-documents/Q3 roadmap.pdf.json',
      pinned: true,
    );
    await openFiles(tester, llm: llm);
    expect(inPane(find.text('Pinned')), findsOneWidget);
  });

  testWidgets('View extracted text shows the text, saves it, and goes back', (
    tester,
  ) async {
    final h = await openFiles(tester);
    await tester.tap(inPane(control('View extracted text of Q3 roadmap.pdf')));
    await tester.pumpAndSettle();
    expect(paneTitle(tester), 'Q3 roadmap.pdf');
    expect(inPane(find.text('The text of Q3 roadmap.pdf.')), findsOneWidget);
    await tester.tap(inPane(control('Download text')));
    await tester.pumpAndSettle();
    expect(
      utf8.decode(h.saved['Q3 roadmap.pdf.txt']!),
      'The text of Q3 roadmap.pdf.',
    );
    await tester.tap(inPane(control('Documents')));
    await tester.pumpAndSettle();
    expect(h.files.reading, isNull);
    expect(paneTitle(tester), 'Documents');
  });

  testWidgets('a document whose text the server left out has no download', (
    tester,
  ) async {
    final llm = planningServer()
      ..textless.add('custom-documents/Q3 roadmap.pdf.json');
    await openFiles(tester, llm: llm);
    await tester.tap(inPane(control('View extracted text of Q3 roadmap.pdf')));
    await tester.pumpAndSettle();
    expect(
      inPane(find.text('The server did not send this document\'s text.')),
      findsOneWidget,
    );
    expect(inPane(control('Download text')), findsNothing);
  });

  testWidgets('a document\'s row saves its text', (tester) async {
    final h = await openFiles(tester);
    await tester.tap(inPane(control('Download text of Q3 roadmap.pdf')));
    await tester.pumpAndSettle();
    expect(
      utf8.decode(h.saved['Q3 roadmap.pdf.txt']!),
      'The text of Q3 roadmap.pdf.',
    );
    expect(h.files.reading, isNull);
  });

  testWidgets('a row\'s download of a document without text says why', (
    tester,
  ) async {
    final llm = planningServer()
      ..textless.add('custom-documents/Q3 roadmap.pdf.json');
    final h = await openFiles(tester, llm: llm);
    await tester.tap(inPane(control('Download text of Q3 roadmap.pdf')));
    await tester.pumpAndSettle();
    expect(h.saved, isEmpty);
    expect(inPane(find.text('Could not save Q3 roadmap.pdf')), findsOneWidget);
    expect(
      inPane(find.text('The server did not send this document\'s text.')),
      findsOneWidget,
    );
  });

  testWidgets('a text that cannot be read says why', (tester) async {
    final llm = planningServer()
      ..errors['document'] = const ApiException('The server is down.');
    await openFiles(tester, llm: llm);
    await tester.tap(inPane(control('View extracted text of Q3 roadmap.pdf')));
    await tester.pumpAndSettle();
    expect(find.text('Could not read Q3 roadmap.pdf'), findsOneWidget);
    expect(find.text('The server is down.'), findsOneWidget);
  });

  testWidgets(
    'a file dropped on the adders waits, then goes to the workspace',
    (tester) async {
      final llm = planningServer();
      await openFiles(tester, llm: llm);
      final queue = tester.widget<UploadQueue>(
        inPane(find.byType(UploadQueue)),
      );
      expect(queue.trigger, isNotNull);
      await queue.onSend([
        UploadFile(name: 'a.md', read: () async => [1]),
      ]);
      await tester.pumpAndSettle();
      expect(llm.calls, contains('upload:a.md'));
      expect(llm.spaces.first.docs, hasLength(3));
    },
  );

  testWidgets('Test a question opens under the adders and Done closes it', (
    tester,
  ) async {
    await openFiles(tester);
    await tester.tap(inPane(control('Test a question')));
    await tester.pumpAndSettle();
    expect(inPane(control('Test a question')), findsNothing);
    expect(inPane(control('Done')), findsOneWidget);
    await tester.tap(inPane(control('Done')));
    await tester.pumpAndSettle();
    expect(inPane(control('Test a question')), findsOneWidget);
  });

  testWidgets('Instructions is the workspace\'s PROMPT.md', (tester) async {
    final llm = planningServer();
    final h = await openFiles(tester, llm: llm);
    await tapSection(tester, 'Instructions');
    expect(paneTitle(tester), 'Instructions');
    expect(h.files.selected, promptPath('q3'));
    await tester.enterText(inPane(find.byType(TextField)), 'Answer in French.');
    await tester.pump();
    await tester.tap(inPane(control('Save')));
    await tester.pumpAndSettle();
    expect(llm.spaces.first.prompt, 'Answer in French.');
    expect(h.files.essentials, isTrue);
  });

  testWidgets('Answer settings names the mode as the composer does', (
    tester,
  ) async {
    final llm = planningServer();
    await openFiles(tester, llm: llm);
    await tapSection(tester, 'Answer settings');
    expect(paneTitle(tester), 'Answer settings');
    expect(inPane(find.text('Answer from')), findsOneWidget);
    expect(inPane(find.text('Chat mode')), findsNothing);
    expect(inPane(find.text('When the files do not cover it')), findsOneWidget);
    expect(inPane(find.text('Query refusal response')), findsNothing);
    for (final label in [
      'Files, knowledge & tools',
      'Files & knowledge',
      'Files only',
    ]) {
      expect(inPane(control(label)), findsOneWidget, reason: label);
    }
    await tester.tap(inPane(control('Files only')));
    await tester.pump();
    await tester.tap(inPane(control('Save')));
    await tester.pumpAndSettle();
    expect(llm.spaces.first.settings['chatMode'], 'query');

    // All files keeps AnythingLLM's names, on the same file.
    await tester.tap(inSidebar(control('All files')));
    await tester.pumpAndSettle();
    expect(paneTitle(tester), 'settings.json');
    expect(inPane(find.text('Chat mode')), findsOneWidget);
    expect(inPane(control('Query')), findsOneWidget);
    expect(inPane(find.text('Query refusal response')), findsOneWidget);
    expect(inSidebar(control('settings.json')), findsOneWidget);
  });

  testWidgets('Essentials follows another workspace opened meanwhile', (
    tester,
  ) async {
    final h = await openFiles(tester);
    await tapSection(tester, 'Instructions');
    await h.chat.select('household');
    await tester.pumpAndSettle();
    expect(h.files.selected, promptPath('household'));
    expect(paneTitle(tester), 'Instructions');
    await tapSection(tester, 'Documents, 0 on');
    expect(inPane(find.text('No documents yet.')), findsOneWidget);
  });

  testWidgets(
    'on a phone Files is the workspace\'s pages, and Back steps out',
    (tester) async {
      final h = await pumpApp(
        tester,
        llm: planningServer(),
        size: const Size(390, 844),
      );
      h.shell.showPane(Pane.files);
      await tester.pumpAndSettle();
      final pages = find.byType(WorkspacePages);
      expect(pages, findsOneWidget);
      expect(find.byType(FileTree), findsNothing);
      Finder inPages(Finder f) => find.descendant(of: pages, matching: f);
      expect(inPages(find.text('Workspace')), findsOneWidget);
      expect(inPages(find.text('Q3 planning')), findsOneWidget);
      expect(inPages(find.text('2 chats')), findsOneWidget);
      expect(
        inPages(find.text('2 documents, 2 used in answers')),
        findsOneWidget,
      );
      expect(inPages(find.text('2 of 2 used in answers')), findsOneWidget);
      await tester.tap(inPages(find.text('Answer from')));
      await tester.pumpAndSettle();
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
    },
  );

  testWidgets('the sections list only while Essentials is on', (tester) async {
    final h = await openFiles(tester);
    await tester.tap(inSidebar(control('All files')));
    await tester.pumpAndSettle();
    expect(find.byType(EssentialsList), findsNothing);
    expect(inSidebar(control('Q3 planning')), findsOneWidget);
    await tester.tap(inSidebar(control('Essentials')));
    await tester.pumpAndSettle();
    expect(find.byType(EssentialsList), findsOneWidget);
    expect(h.files.selected, docsPath('q3'));
  });

  testWidgets("a phone's Instructions say whose answers they open", (
    tester,
  ) async {
    final llm = planningServer()
      ..spaces[0].prompt = 'Answer from the documents.';
    final h = await pumpApp(tester, llm: llm, size: const Size(390, 844));
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(WorkspacePages),
        matching: find.text('Instructions'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('What every answer in Q3 planning is told first.'),
      findsOneWidget,
    );
  });

  testWidgets("a phone's document opens its text, with Download and Remove", (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      llm: planningServer(),
      size: const Size(390, 844),
    );
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();
    await tester.tap(control('View extracted text of Q3 roadmap.pdf'));
    await tester.pumpAndSettle();
    expect(control('Download the extracted text'), findsOneWidget);
    expect(find.text('Used in answers'), findsOneWidget);
    await tester.tap(control('Download the extracted text'));
    await tester.pumpAndSettle();
    expect(h.saved.keys, contains('Q3 roadmap.pdf.txt'));
    await tapVisible(tester, control('Remove from workspace'));
    await tester.pumpAndSettle();
    expect(h.files.reading, isNull);
    expect(
      h.sources.files.where((f) => f.on).map((f) => f.title),
      isNot(contains('Q3 roadmap.pdf')),
    );
    // The undo for the removal lets go.
    await tester.pump(const Duration(seconds: 7));
  });
}
