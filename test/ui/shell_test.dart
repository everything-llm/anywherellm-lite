import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/ui/settings/settings_dialog.dart';
import 'package:anywherellm/ui/sidebar.dart';
import 'package:anywherellm/ui/sources/sources_panel.dart';
import 'package:anywherellm/ui/widgets/controls.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// A control by the label a screen reader hears.
Finder control(String label) => find.byWidgetPredicate(
  (widget) => widget is Tappable && widget.label == label,
);

Finder inSidebar(String text) =>
    find.descendant(of: find.byType(Sidebar), matching: find.text(text));

Finder inSources(Finder finder) =>
    find.descendant(of: find.byType(SourcesPanel), matching: finder);

Finder get message => find.bySemanticsLabel('Message');

/// The text field that has the focus, or else the composer.
Finder get typingInto {
  final focused = find.byWidgetPredicate(
    (widget) => widget is EditableText && widget.focusNode.hasFocus,
  );
  return focused.evaluate().isEmpty ? find.byType(EditableText).last : focused;
}

/// Types [text] where the focus is and presses Enter. Pumps a fixed time rather than settling,
/// since the caret of a streaming answer never stops blinking.
Future<void> typeAndEnter(WidgetTester tester, String text) async {
  await tester.enterText(typingInto, text);
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  group('a wide window', () {
    testWidgets('shows the workspaces, the chat and its Sources side by side', (
      tester,
    ) async {
      await pumpApp(tester, llm: planningServer());
      expect(inSidebar('Q3 planning'), findsOneWidget);
      expect(inSidebar('2 docs'), findsOneWidget);
      expect(inSidebar('Budget questions'), findsOneWidget);
      expect(inSidebar('Quarter priorities'), findsOneWidget);
      expect(inSidebar('AnythingLLM · key set'), findsOneWidget);
      expect(find.text('About 40k.'), findsOneWidget);
      expect(inSources(find.text('Q3 roadmap.pdf')), findsOneWidget);
      expect(find.byTooltip('Workspaces'), findsNothing);
    });

    testWidgets('a workspace with no chats invites a first question', (
      tester,
    ) async {
      await pumpApp(tester, llm: planningServer());
      await tester.tap(inSidebar('Household'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ask anything about what'), findsOneWidget);
      expect(find.text('No files yet.'), findsOneWidget);
      await tester.tap(control('What can I do here?'));
      await tester.pump();
      expect(find.text('What can I do here?'), findsWidgets);
    });

    testWidgets(
      'Enter sends, the answer streams, and its citation opens Sources',
      (tester) async {
        final llm = planningServer()
          ..hold = true
          ..cited = ['Q3 roadmap.pdf'];
        final h = await pumpApp(tester, llm: llm);
        await typeAndEnter(tester, 'What is due?');
        expect(find.text('What is due?'), findsOneWidget);
        expect(find.byType(Caret), findsOneWidget);
        expect(control('Stop'), findsOneWidget);

        llm.chat!.add(const TextChunk('The roadmap.'));
        llm.chat!.add(const ChatDone([Citation('Q3 roadmap.pdf')]));
        await llm.chat!.close();
        await tester.pumpAndSettle();
        expect(find.byType(Caret), findsNothing);
        expect(control('Send'), findsOneWidget);

        h.shell.closeSources();
        await tester.pumpAndSettle();
        await tester.tap(control('Source 1: Q3 roadmap.pdf').last);
        await tester.pump();
        expect(h.shell.sourcesOpen, isTrue);
        expect(h.sources.flashed, 'custom-documents/Q3 roadmap.pdf.json');
        await tester.pumpAndSettle(const Duration(seconds: 2));
      },
    );

    testWidgets('Shift+Enter starts a new line instead of sending', (
      tester,
    ) async {
      final llm = planningServer();
      await pumpApp(tester, llm: llm);
      await tester.enterText(find.byType(TextField).last, 'one');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
    });

    testWidgets('Stop ends the answer', (tester) async {
      final llm = planningServer()..hold = true;
      final h = await pumpApp(tester, llm: llm);
      await typeAndEnter(tester, 'Go');
      await tester.tap(control('Stop'));
      await tester.pumpAndSettle();
      expect(find.text('Stopped.'), findsOneWidget);
      expect(h.chat.busy, isFalse);
    });

    testWidgets('+ makes a workspace from the name typed', (tester) async {
      final llm = planningServer();
      await pumpApp(tester, llm: llm);
      await tester.tap(control('New workspace'));
      await tester.pumpAndSettle();
      await typeAndEnter(tester, 'Reading notes');
      expect(llm.calls, contains('createWorkspace:Reading notes'));
      expect(inSidebar('Reading notes'), findsOneWidget);
    });

    testWidgets('Esc leaves the new workspace name without making one', (
      tester,
    ) async {
      final llm = planningServer();
      await pumpApp(tester, llm: llm);
      await tester.tap(control('New workspace'));
      await tester.pumpAndSettle();
      await tester.enterText(typingInto, 'x');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      // Only the composer is left to type in; a selectable answer is read-only.
      expect(
        find.byWidgetPredicate((w) => w is EditableText && !w.readOnly),
        findsOneWidget,
      );
      expect(llm.calls, isNot(contains('createWorkspace:x')));
    });

    testWidgets('the pencil renames the chat on Enter', (tester) async {
      final llm = planningServer();
      await pumpApp(tester, llm: llm);
      await tester.tap(control('Rename chat'));
      await tester.pumpAndSettle();
      await typeAndEnter(tester, 'Money');
      expect(llm.calls, contains('renameThread:budget:Money'));
      expect(inSidebar('Money'), findsOneWidget);
    });

    testWidgets('the trash deletes the chat', (tester) async {
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm);
      await tester.tap(control('Delete chat'));
      await tester.pumpAndSettle();
      expect(llm.calls, contains('deleteThread:budget'));
      expect(inSidebar('Budget questions'), findsNothing);
      expect(h.chat.activeThread, 'priorities');
    });

    testWidgets('the pencil renames the workspace on Enter', (tester) async {
      final llm = planningServer();
      await pumpApp(tester, llm: llm);
      await tester.tap(control('Rename workspace'));
      await tester.pumpAndSettle();
      await typeAndEnter(tester, 'Q4 planning');
      expect(llm.calls, contains('renameWorkspace:q3:Q4 planning'));
      expect(inSidebar('Q4 planning'), findsOneWidget);
    });

    testWidgets('the workspace trash asks first, and Cancel keeps it', (
      tester,
    ) async {
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm);
      await tester.tap(control('Delete workspace'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Delete Q3 planning and its 2 chats? Its documents stay in the library.',
        ),
        findsOneWidget,
      );
      await tester.tap(control('Cancel'));
      await tester.pumpAndSettle();
      expect(llm.calls, isNot(contains('deleteWorkspace:q3')));
      await tester.tap(control('Delete workspace'));
      await tester.pumpAndSettle();
      await tester.tap(control('Delete'));
      await tester.pumpAndSettle();
      expect(llm.calls, contains('deleteWorkspace:q3'));
      expect(inSidebar('Q3 planning'), findsNothing);
      expect(h.chat.activeSlug, 'household');
    });

    testWidgets('Esc leaves the workspace delete question', (tester) async {
      final llm = planningServer();
      await pumpApp(tester, llm: llm);
      await tester.tap(control('Delete workspace'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(control('Cancel'), findsNothing);
      expect(llm.calls, isNot(contains('deleteWorkspace:q3')));
    });

    testWidgets('a workspace cannot be deleted while it answers', (
      tester,
    ) async {
      final llm = planningServer()..hold = true;
      await pumpApp(tester, llm: llm);
      await typeAndEnter(tester, 'Go');
      await tester.tap(control('Delete workspace'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(control('Cancel'), findsNothing);
    });

    testWidgets('the chat mode chooser shows and changes the workspace mode', (
      tester,
    ) async {
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm);
      expect(inSources(find.text(ChatMode.automatic.about)), findsOneWidget);
      await tester.tap(inSources(control('Query')));
      await tester.pumpAndSettle();
      expect(llm.spaces.first.settings['chatMode'], 'query');
      expect(h.sources.chatMode, ChatMode.query);
      expect(inSources(find.text(ChatMode.query.about)), findsOneWidget);
    });

    testWidgets('an empty chat and the composer follow the chat mode', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: planningServer());
      h.chat.newChat();
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Answers draw on the switched-on files, and on tools such as web search when they need them.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ask anything…'), findsOneWidget);
      await tester.tap(inSources(control('Query')));
      await tester.pumpAndSettle();
      expect(
        find.text('Answers come only from the switched-on files.'),
        findsOneWidget,
      );
      expect(find.text('Ask about your files…'), findsOneWidget);
    });

    testWidgets('the chat mode waits while an answer runs', (tester) async {
      final llm = planningServer()..hold = true;
      await pumpApp(tester, llm: llm);
      await typeAndEnter(tester, 'Go');
      await tester.tap(inSources(control('Chat')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(llm.calls, isNot(contains('updateWorkspace:q3')));
    });

    testWidgets(
      'an agent answer shows its status, then folds its many sources',
      (tester) async {
        final llm = planningServer()..hold = true;
        final h = await pumpApp(tester, llm: llm);
        await typeAndEnter(tester, 'News?');
        llm.chat!.add(const StatusChunk('Running web-browsing'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Running web-browsing'), findsOneWidget);
        llm.chat!
          ..add(const WholeAnswer('Headline'))
          ..add(ChatDone([for (var i = 1; i <= 9; i++) Citation('Story $i')]));
        await llm.chat!.close();
        await tester.pumpAndSettle();
        expect(find.text('Running web-browsing'), findsNothing);
        expect(h.chat.turns.last.text, 'Headline');
        expect(control('Source 5: Story 5'), findsOneWidget);
        expect(control('Source 6: Story 6'), findsNothing);
        await tester.tap(control('4 more sources'));
        await tester.pumpAndSettle();
        expect(control('Source 9: Story 9'), findsOneWidget);
      },
    );

    testWidgets('a file switched off is dimmed and counted out', (
      tester,
    ) async {
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm);
      await tester.tap(find.byType(AppSwitch).first);
      await tester.pumpAndSettle();
      expect(h.sources.onCount, 1);
      expect(
        find.descendant(of: control('Sources'), matching: find.text('1')),
        findsOneWidget,
      );
    });

    testWidgets('removing a file can be undone from the toast', (tester) async {
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm);
      await tester.tap(control('Remove Q3 roadmap.pdf'));
      await tester.pumpAndSettle();
      expect(find.text('Removed Q3 roadmap.pdf'), findsOneWidget);
      await tester.tap(control('Undo'));
      await tester.pumpAndSettle();
      expect(h.sources.files, hasLength(2));
      expect(find.text('Removed Q3 roadmap.pdf'), findsNothing);
    });

    testWidgets('Sources closes and opens from the header', (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      await tester.tap(control('Close'));
      await tester.pumpAndSettle();
      expect(h.shell.sourcesOpen, isFalse);
      await tester.tap(control('Sources'));
      await tester.pumpAndSettle();
      expect(h.shell.sourcesOpen, isTrue);
    });
  });

  group('Settings', () {
    testWidgets('with no key, the composer sends the person to Settings', (
      tester,
    ) async {
      final h = await pumpApp(tester, connection: null);
      expect(find.text('Welcome to AnywhereLLM'), findsOneWidget);
      expect(inSidebar('AnythingLLM · no key'), findsOneWidget);
      await tester.tap(control('Open Settings'));
      await tester.pumpAndSettle();
      expect(h.shell.settingsOpen, isTrue);
      expect(find.text('Missing'), findsOneWidget);
    });

    testWidgets('a key the server takes is saved and the workspaces load', (
      tester,
    ) async {
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm, connection: null);
      h.shell.openSettings();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel('AnythingLLM developer API key').last,
        'K9',
      );
      await tester.tap(control('Save key'));
      await tester.pumpAndSettle();
      expect(h.store.saved?.apiKey, 'K9');
      expect(find.text('The key was saved.'), findsOneWidget);
      expect(find.text('Set'), findsOneWidget);
      expect(inSidebar('Q3 planning'), findsOneWidget);
    });

    testWidgets('a key the server refuses is not saved', (tester) async {
      final llm = planningServer()
        ..verifyError = const ApiException('The server rejected the key.');
      final h = await pumpApp(tester, llm: llm, connection: null);
      h.shell.openSettings();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel('AnythingLLM developer API key').last,
        'WRONG',
      );
      await tester.tap(control('Save key'));
      await tester.pumpAndSettle();
      expect(h.store.saved, isNull);
      expect(find.text('The server rejected the key.'), findsOneWidget);
      expect(find.text('Missing'), findsOneWidget);
    });

    testWidgets('a replaced key closes the form once saved', (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      h.shell.openSettings();
      await tester.pumpAndSettle();
      await tester.tap(control('Replace'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel('AnythingLLM developer API key').last,
        'K9',
      );
      await tester.tap(control('Save key'));
      await tester.pumpAndSettle();
      expect(h.store.saved?.apiKey, 'K9');
      expect(control('Save key'), findsNothing);
      expect(control('Replace'), findsOneWidget);
    });

    testWidgets('Forget asks once more, then deletes the key', (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      h.shell.openSettings();
      await tester.pumpAndSettle();
      await tester.tap(control('Forget'));
      await tester.pumpAndSettle();
      expect(control('Delete it?'), findsOneWidget);
      await tester.tap(control('Delete it?'));
      await tester.pumpAndSettle();
      expect(h.settings.configured, isFalse);
      expect(find.text('The saved key was deleted.'), findsOneWidget);
    });

    testWidgets('Esc and Done close it', (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      h.shell.openSettings();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsNothing);
      h.shell.openSettings();
      await tester.pumpAndSettle();
      await tester.tap(control('Done'));
      await tester.pumpAndSettle();
      expect(h.shell.settingsOpen, isFalse);
    });
  });

  group('a narrow window', () {
    testWidgets('below 1120, Sources is a drawer over the chat', (
      tester,
    ) async {
      final h = await pumpApp(
        tester,
        llm: planningServer(),
        size: const Size(1000, 800),
        sourcesOpen: false,
      );
      expect(
        tester.getTopLeft(find.byType(SourcesPanel)).dx,
        greaterThanOrEqualTo(1000),
      );
      await tester.tap(control('Sources'));
      await tester.pumpAndSettle();
      expect(tester.getTopRight(find.byType(SourcesPanel)).dx, 1000);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.shell.sourcesOpen, isFalse);
    });

    testWidgets('Sources open in the layout does not become an open drawer', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: planningServer());
      expect(h.shell.sourcesOpen, isTrue);
      tester.view.physicalSize = const Size(1000, 800);
      await tester.pumpAndSettle();
      expect(h.shell.sourcesOpen, isFalse);
      expect(
        tester.getTopLeft(find.byType(SourcesPanel)).dx,
        greaterThanOrEqualTo(1000),
      );
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
      expect(h.shell.sourcesOpen, isTrue);
    });

    testWidgets('below 820, the sidebar is a drawer behind the menu button', (
      tester,
    ) async {
      final h = await pumpApp(
        tester,
        llm: planningServer(),
        size: const Size(780, 800),
        sourcesOpen: false,
      );
      expect(tester.getTopLeft(find.byType(Sidebar)).dx, lessThan(0));
      await tester.tap(find.byTooltip('Workspaces'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(Sidebar)).dx, 0);
      await tester.tap(inSidebar('Quarter priorities'));
      await tester.pumpAndSettle();
      expect(h.chat.activeThread, 'priorities');
      expect(h.shell.sideOpen, isFalse);
    });
  });
}
