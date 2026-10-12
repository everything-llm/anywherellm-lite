import 'dart:convert';

import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/files.dart';
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

Finder inTree(String label) =>
    find.descendant(of: find.byType(FileTree), matching: control(label));

Finder inPane(Finder finder) =>
    find.descendant(of: find.byType(FilesView), matching: finder);

/// Taps the tree's row [label], switching the sidebar from Essentials to All files first when
/// the tree is not showing.
Future<void> tapTree(WidgetTester tester, String label) async {
  if (inTree(label).evaluate().isEmpty) {
    await tester.tap(inTree('All files'));
    await tester.pumpAndSettle();
  }
  await tester.tap(inTree(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Files replaces the chat and Sources, and Chats brings them back',
    (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      await fromMenu(tester, 'Files and settings');
      expect(h.shell.pane, Pane.files);
      expect(find.byType(FileTree), findsOneWidget);
      expect(find.byType(SourcesPanel).hitTestable(), findsNothing);
      expect(find.byType(ChatView).hitTestable(), findsNothing);
      expect(inTree('Documents, 2 on'), findsOneWidget);
      expect(inTree('Q3 planning'), findsNothing);
      await tester.tap(inTree('All files'));
      await tester.pumpAndSettle();
      expect(inTree('Q3 planning'), findsOneWidget);
      expect(inTree('custom-documents'), findsOneWidget);
      await tester.tap(control('Back to chats'));
      await tester.pumpAndSettle();
      expect(find.byType(FileTree), findsNothing);
      expect(find.text('About 40k.'), findsOneWidget);
      await fromMenu(tester, 'Files and settings');
      await fromMenu(tester, 'Chats');
      expect(h.shell.pane, Pane.chats);
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
    await tester.tap(inPane(control('Edit as JSON')));
    await tester.pumpAndSettle();
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

  testWidgets('Edit as JSON shows a mode changed in Sources meanwhile', (
    tester,
  ) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm);
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await tapTree(tester, 'Q3 planning');
    await tapTree(tester, 'settings.json');
    await tester.tap(inPane(control('Edit as JSON')));
    await tester.pumpAndSettle();
    h.shell.showPane(Pane.chats);
    await tester.pumpAndSettle();
    await h.sources.setChatMode(ChatMode.query);
    await tester.pumpAndSettle();
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    final shown = tester.widget<TextField>(inPane(find.byType(TextField)));
    expect(shown.controller!.text, contains('"chatMode": "query"'));
  });

  testWidgets('saving from Edit as JSON stays on the JSON', (tester) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm);
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await tapTree(tester, 'Q3 planning');
    await tapTree(tester, 'settings.json');
    await tester.tap(inPane(control('Edit as JSON')));
    await tester.pumpAndSettle();
    final edited = const JsonEncoder.withIndent('  ')
        .convert({...llm.spaces.first.settings, 'topN': 6});
    await tester.enterText(inPane(find.byType(TextField)), edited);
    await tester.pump();
    await tester.tap(inPane(control('Save')));
    await tester.pumpAndSettle();
    expect(llm.spaces.first.settings['topN'], 6);
    expect(inPane(control('Edit as JSON')), findsNothing);
    await tapTree(tester, 'PROMPT.md');
    await tapTree(tester, 'settings.json');
    expect(inPane(control('Edit as JSON')), findsOneWidget);
  });

  group('the settings form', () {
    Future<FakeAnythingLlm> openSettings(
      WidgetTester tester, {
      Map<String, Object?> settings = const {},
    }) async {
      final llm = planningServer();
      llm.spaces.first.settings.addAll(settings);
      // Tall, so the whole form is on screen.
      final h = await pumpApp(tester, llm: llm, size: const Size(1280, 1800));
      h.shell.showPane(Pane.files);
      await tester.pumpAndSettle();
      await tapTree(tester, 'Q3 planning');
      await tapTree(tester, 'settings.json');
      return llm;
    }

    testWidgets('shows the settings as a form with Save off until a change', (
      tester,
    ) async {
      await openSettings(tester);
      expect(inPane(find.text('Chat mode')), findsOneWidget);
      expect(inPane(find.text('Max context snippets')), findsOneWidget);
      expect(inPane(find.text('Minimum relevance')), findsOneWidget);
      final save = tester.widget<Tappable>(inPane(control('Save')));
      expect(save.onTap, isNull);
    });

    testWidgets('saves only what changed', (tester) async {
      final llm = await openSettings(tester);
      await tester.tap(inPane(control('Query')));
      await tester.pump();
      await tester.enterText(
        inPane(find.widgetWithText(TextField, '4')).first,
        '9',
      );
      await tester.pump();
      llm.calls.clear();
      await tester.tap(inPane(control('Save')));
      await tester.pumpAndSettle();
      expect(llm.calls, contains('updateWorkspace:q3'));
      expect(llm.spaces.first.settings['chatMode'], 'query');
      expect(llm.spaces.first.settings['topN'], 9);
    });

    testWidgets('a text setting is saved without its spaces', (tester) async {
      final llm = await openSettings(tester);
      await tester.enterText(
        typingField(inPane(find.bySemanticsLabel('LLM model'))),
        ' gpt-4o ',
      );
      await tester.pump();
      await tester.tap(inPane(control('Save')));
      await tester.pumpAndSettle();
      expect(llm.spaces.first.settings['chatModel'], 'gpt-4o');
    });

    testWidgets('a value left as the server had it is not sent', (
      tester,
    ) async {
      final llm = await openSettings(
        tester,
        settings: {'queryRefusalResponse': '', 'chatModel': 'gpt-4o\n'},
      );
      expect(tester.widget<Tappable>(inPane(control('Save'))).onTap, isNull);
      await tester.enterText(
        inPane(find.widgetWithText(TextField, '4')).first,
        '9',
      );
      await tester.pump();
      await tester.tap(inPane(control('Save')));
      await tester.pumpAndSettle();
      expect(llm.spaces.first.settings['topN'], 9);
      expect(llm.spaces.first.settings['queryRefusalResponse'], '');
      expect(llm.spaces.first.settings['chatModel'], 'gpt-4o\n');
    });

    testWidgets('a bad number is flagged and nothing is sent', (tester) async {
      final llm = await openSettings(tester);
      await tester.enterText(
        inPane(find.widgetWithText(TextField, '4')).first,
        'many',
      );
      await tester.pump();
      llm.calls.clear();
      await tester.tap(inPane(control('Save')));
      await tester.pumpAndSettle();
      expect(inPane(find.text('A whole number.')), findsOneWidget);
      expect(llm.calls, isNot(contains('updateWorkspace:q3')));
    });

    testWidgets('a value the server refuses shows why and keeps the draft', (
      tester,
    ) async {
      final llm = await openSettings(tester);
      await tester.enterText(
        inPane(find.widgetWithText(TextField, '4')).first,
        '0',
      );
      await tester.pump();
      await tester.tap(inPane(control('Save')));
      await tester.pumpAndSettle();
      expect(find.text('Could not save settings.json'), findsOneWidget);
      expect(llm.calls, isNot(contains('updateWorkspace:q3')));
    });

    testWidgets('a similarity preset and Revert', (tester) async {
      final llm = await openSettings(tester);
      await tester.tap(inPane(control('High')));
      await tester.pump();
      await tester.tap(inPane(control('Revert')));
      await tester.pump();
      expect(tester.widget<Tappable>(inPane(control('Save'))).onTap, isNull);
      await tester.tap(inPane(control('High')));
      await tester.pump();
      await tester.tap(inPane(control('Save')));
      await tester.pumpAndSettle();
      expect(llm.spaces.first.settings['similarityThreshold'], 0.75);
    });
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

  testWidgets('a delete question stays with its document', (tester) async {
    final h = await pumpApp(tester, llm: planningServer());
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await tapTree(tester, 'custom-documents');
    await tapTree(tester, 'Q3 roadmap.pdf');
    await tester.tap(inPane(control('Delete…')));
    await tester.pumpAndSettle();
    await tapTree(tester, 'Customer interviews.docx');
    expect(
      find.textContaining('Delete Customer interviews.docx'),
      findsNothing,
    );
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

  testWidgets('a delete question reads at regular weight', (tester) async {
    final h = await pumpApp(tester, llm: planningServer());
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await tapTree(tester, 'custom-documents');
    await tapTree(tester, 'Q3 roadmap.pdf');
    await tester.tap(inPane(control('Delete…')));
    await tester.pumpAndSettle();
    final question = tester.widget<Text>(
      find.textContaining('Delete Q3 roadmap.pdf'),
    );
    expect(question.style!.fontWeight, isNot(FontWeight.w600));
    expect(question.style!.fontSize, 14);
  });

  testWidgets('a workspace\'s documents say which are not used in answers', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer());
    await h.sources.toggle(h.sources.files.first);
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await h.files.reveal(docsPath('q3'));
    await tester.pumpAndSettle();
    expect(inPane(find.text('120 words')), findsOneWidget);
    expect(
      inPane(find.text('120 words · Not used in answers')),
      findsOneWidget,
    );
    await tester.tap(
      inPane(control('Q3 roadmap.pdf, 120 words · Not used in answers')),
    );
    await tester.pumpAndSettle();
    expect(h.files.selected, '/library/custom-documents/Q3 roadmap.pdf.json');
  });
}
