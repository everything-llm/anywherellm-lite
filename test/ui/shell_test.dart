import 'dart:async';

import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/ui/chat/chat_view.dart';
import 'package:anywherellm/ui/settings/settings_dialog.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/sidebar.dart';
import 'package:anywherellm/ui/sources/sources_panel.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/widgets/confirm_box.dart';
import 'package:anywherellm/ui/widgets/controls.dart';
import 'package:anywherellm/ui/widgets/fields.dart';
import 'package:anywherellm/ui/widgets/pane_header.dart';
import 'package:anywherellm/ui/widgets/qr_mark.dart';
import 'package:anywherellm/ui/widgets/sheet.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

Finder inSidebar(String text) =>
    find.descendant(of: find.byType(Sidebar), matching: find.text(text));

Finder inSources(Finder finder) =>
    find.descendant(of: find.byType(SourcesPanel), matching: finder);

Finder inChat(Finder finder) =>
    find.descendant(of: find.byType(ChatView), matching: finder);

Finder get message => find.bySemanticsLabel('Message');

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
      expect(inSidebar('Connected to h'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Tappable && w.tooltip == 'https://h:3001',
        ),
        findsOneWidget,
      );
      expect(find.text('About 40k.'), findsOneWidget);
      expect(inSources(find.text('Q3 roadmap.pdf')), findsOneWidget);
      expect(find.byTooltip('Workspaces'), findsNothing);
    });

    testWidgets('says when the saved server does not answer', (tester) async {
      final llm = planningServer()
        ..errors['workspaces'] = const ApiException(
          'Could not reach the server.',
        );
      await pumpApp(tester, llm: llm);
      expect(inSidebar('Connection problem'), findsOneWidget);
      expect(inSidebar('Connected to h'), findsNothing);
    });

    testWidgets('a workspace with no chats invites a first question', (
      tester,
    ) async {
      await pumpApp(tester, llm: planningServer());
      await fromMenu(tester, 'Household');
      expect(
        find.text('Ask about Household.', findRichText: true),
        findsOneWidget,
      );
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
        expect(find.byType(WaitingDots), findsOneWidget);
        expect(find.byType(Caret), findsNothing);
        expect(control('Stop the answer'), findsOneWidget);

        llm.chat!.add(const TextChunk('The roadmap.'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(WaitingDots), findsNothing);
        expect(find.byType(Caret), findsOneWidget);
        llm.chat!.add(const ChatDone([Citation('Q3 roadmap.pdf')]));
        await llm.chat!.close();
        await tester.pumpAndSettle();
        expect(find.byType(Caret), findsNothing);
        expect(find.byType(WaitingDots), findsNothing);
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

    testWidgets('on a phone a citation opens the passages read from its file', (
      tester,
    ) async {
      final llm = planningServer()..hold = true;
      final h = await pumpApp(tester, llm: llm, size: const Size(390, 844));
      await typeAndEnter(tester, 'What is the budget?');
      llm.chat!.add(const TextChunk('About 40k.'));
      llm.chat!.add(
        const ChatDone([
          Citation(
            'Q3 roadmap.pdf',
            passages: [
              Passage('Customer research: about 40k.', score: 0.82),
              Passage('Cut the study first.', score: 0.47),
            ],
          ),
        ]),
      );
      await llm.chat!.close();
      await tester.pumpAndSettle();
      // The chat's earlier answer cites the file with no passages, which flashes it instead.
      await tester.tap(find.byTooltip('Passages read'));
      await tester.pumpAndSettle();
      final sheet = find.byType(SheetFrame);
      expect(
        find.descendant(of: sheet, matching: find.text('Passages read')),
        findsOneWidget,
      );
      expect(find.text('2 passages, closest first'), findsOneWidget);
      expect(find.text('82% match'), findsOneWidget);
      expect(find.text('47% match'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('82% match')).dy,
        lessThan(tester.getTopLeft(find.text('47% match')).dy),
      );
      expect(h.shell.sourcesOpen, isFalse);
      expect(tester.takeException(), isNull);
      await tester.tap(control('View extracted text'));
      await tester.pumpAndSettle();
      expect(h.shell.popup.value, isNull);
      expect(h.shell.pane, Pane.files);
      expect(h.files.reading?.title, 'Q3 roadmap.pdf');
    });

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

    testWidgets('a new chat keeps its question on screen while the first '
        'answer runs, whatever redraws the list', (tester) async {
      final llm = planningServer()..hold = true;
      final h = await pumpApp(tester, llm: llm);
      await h.chat.select('household');
      await tester.pump();
      final made = llm.gates['createThread'] = Completer<void>();
      await typeAndEnter(tester, 'What is due?');
      made.complete();
      await tester.pump();
      tester.platformDispatcher.textScaleFactorTestValue = 1.1;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump();
      expect(find.text('What is due?'), findsOneWidget);
      expect(find.byType(WaitingDots), findsOneWidget);
    });

    testWidgets('Stop ends the answer', (tester) async {
      final llm = planningServer()..hold = true;
      final h = await pumpApp(tester, llm: llm);
      await typeAndEnter(tester, 'Go');
      await tester.tap(control('Stop the answer'));
      await tester.pumpAndSettle();
      expect(find.text('Stopped.'), findsOneWidget);
      expect(h.chat.busy, isFalse);
    });

    testWidgets('+ makes a workspace from the name typed', (tester) async {
      final llm = planningServer();
      await pumpApp(tester, llm: llm);
      await fromMenu(tester, 'New workspace');
      await typeAndEnter(tester, 'Reading notes');
      expect(llm.calls, contains('createWorkspace:Reading notes'));
      expect(inSidebar('Reading notes'), findsOneWidget);
    });

    testWidgets('a soft keyboard\'s Done makes the workspace too', (
      tester,
    ) async {
      final llm = planningServer();
      await pumpApp(tester, llm: llm);
      await fromMenu(tester, 'New workspace');
      await tester.enterText(typingInto, 'Travel');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(llm.calls, contains('createWorkspace:Travel'));
    });

    testWidgets('Esc leaves the new workspace name without making one', (
      tester,
    ) async {
      final llm = planningServer();
      await pumpApp(tester, llm: llm);
      await fromMenu(tester, 'New workspace');
      await tester.enterText(typingInto, 'x');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('New workspace name'), findsNothing);
      expect(llm.calls, isNot(contains('createWorkspace:x')));
    });

    testWidgets('the pencil renames the chat on Enter', (tester) async {
      final llm = planningServer();
      await pumpApp(tester, llm: llm);
      await chatAction(tester, 'Rename chat');
      await typeAndEnter(tester, 'Money');
      expect(llm.calls, contains('renameThread:budget:Money'));
      expect(inSidebar('Money'), findsOneWidget);
    });

    testWidgets('the trash deletes the chat', (tester) async {
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm);
      await chatAction(tester, 'Delete chat');
      expect(inSidebar('Budget questions'), findsNothing);
      expect(h.chat.activeThread, 'priorities');
      expect(inSidebar('Deleted Budget questions'), findsOneWidget);
      expect(llm.calls, isNot(contains('deleteThread:budget')));
      await tester.pump(const Duration(seconds: 7));
      expect(llm.calls, contains('deleteThread:budget'));
      await tester.pumpAndSettle();
      expect(inSidebar('Deleted Budget questions'), findsNothing);
    });

    testWidgets('Undo puts a deleted chat back', (tester) async {
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm);
      await chatAction(tester, 'Delete chat');
      await tester.tap(control('Undo'));
      await tester.pumpAndSettle();
      expect(inSidebar('Budget questions'), findsOneWidget);
      expect(h.chat.activeThread, 'budget');
      await tester.pump(const Duration(seconds: 7));
      expect(llm.calls, isNot(contains('deleteThread:budget')));
    });

    testWidgets('the pencil renames the workspace on Enter', (tester) async {
      final llm = planningServer();
      await pumpApp(tester, llm: llm);
      await fromMenu(tester, 'Rename workspace');
      await typeAndEnter(tester, 'Q4 planning');
      expect(llm.calls, contains('renameWorkspace:q3:Q4 planning'));
      expect(inSidebar('Q4 planning'), findsOneWidget);
    });

    testWidgets('the workspace trash asks first, and Cancel keeps it', (
      tester,
    ) async {
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm);
      await fromMenu(tester, 'Delete workspace…');
      expect(
        find.text(
          'Delete Q3 planning and its 2 chats? Its documents stay in the library.',
        ),
        findsOneWidget,
      );
      await tester.tap(control('Cancel'));
      await tester.pumpAndSettle();
      expect(llm.calls, isNot(contains('deleteWorkspace:q3')));
      await fromMenu(tester, 'Delete workspace…');
      await tester.tap(control('Delete'));
      await tester.pumpAndSettle();
      expect(llm.calls, contains('deleteWorkspace:q3'));
      expect(inSidebar('Q3 planning'), findsNothing);
      expect(h.chat.activeSlug, 'household');
    });

    testWidgets('Esc leaves the workspace delete question', (tester) async {
      final llm = planningServer();
      await pumpApp(tester, llm: llm);
      await fromMenu(tester, 'Delete workspace…');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(control('Cancel'), findsNothing);
      expect(llm.calls, isNot(contains('deleteWorkspace:q3')));
    });

    testWidgets('the workspace delete question closes when another opens', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: planningServer());
      await fromMenu(tester, 'Delete workspace…');
      await h.chat.select('household');
      await tester.pumpAndSettle();
      expect(find.byType(ConfirmBox), findsNothing);
      await h.chat.select('q3');
      await tester.pumpAndSettle();
      expect(find.byType(ConfirmBox), findsNothing);
    });

    testWidgets(
      'the workspace delete question closes when it starts answering',
      (tester) async {
        final h = await pumpApp(tester, llm: planningServer()..hold = true);
        await fromMenu(tester, 'Delete workspace…');
        await h.chat.send('Go');
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(ConfirmBox), findsNothing);
      },
    );

    testWidgets('a workspace cannot be deleted while it answers', (
      tester,
    ) async {
      final llm = planningServer()..hold = true;
      await pumpApp(tester, llm: llm);
      await typeAndEnter(tester, 'Go');
      await tester.tap(switcher);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(control('Delete workspace…'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(control('Cancel'), findsNothing);
    });

    testWidgets(
      'an empty chat names its workspace and suggests from its documents',
      (tester) async {
        final h = await pumpApp(tester, llm: planningServer());
        h.chat.newChat();
        await tester.pumpAndSettle();
        expect(
          inChat(find.text('Ask about Q3 planning.', findRichText: true)),
          findsOneWidget,
        );
        expect(control('Summarise Q3 roadmap'), findsOneWidget);
        expect(
          control('Compare Q3 roadmap with Customer interviews'),
          findsOneWidget,
        );
        expect(find.text('Ask anything…'), findsOneWidget);
        // A document switched off is not suggested.
        await tester.tap(find.byType(AppSwitch).first);
        await tester.pumpAndSettle();
        expect(control('Summarise Customer interviews'), findsOneWidget);
        expect(control('Summarise Q3 roadmap'), findsNothing);
      },
    );

    testWidgets(
      'the composer follows the chat mode before the server answers',
      (tester) async {
        final llm = planningServer();
        final h = await pumpApp(tester, llm: llm);
        final gate = llm.gates['updateWorkspace'] = Completer<void>();
        unawaited(h.sources.setChatMode(ChatMode.query));
        await tester.pump();
        expect(find.text('Ask about your files…'), findsOneWidget);
        gate.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets('an unknown chat mode claims only what every mode does', (
      tester,
    ) async {
      final llm = planningServer()
        ..errors['workspace'] = const ApiException('down');
      final h = await pumpApp(tester, llm: llm);
      h.chat.newChat();
      await tester.pumpAndSettle();
      expect(h.sources.chatMode.value, isNull);
      expect(find.text('Ask about your files…'), findsOneWidget);
    });

    testWidgets('the slash menu says why the server\'s commands are missing', (
      tester,
    ) async {
      final llm = planningServer()
        ..errors['slashCommands'] = const ApiException('no', status: 403);
      await pumpApp(tester, llm: llm);
      await tester.enterText(typingInto, '/');
      await tester.pumpAndSettle();
      expect(
        control('/reset: Clear the chat history and begin a new chat'),
        findsOneWidget,
      );
      expect(find.textContaining('This server has a password'), findsOneWidget);
    });

    testWidgets(
      'the server address is a web address, and the password and the key are left out of autofill',
      (tester) async {
        final h = await pumpApp(
          tester,
          llm: planningServer(),
          connection: null,
        );
        h.shell.openSettings();
        await tester.pumpAndSettle();
        List<TextField> fields() => tester
            .widgetList<TextField>(
              find.descendant(
                of: find.byType(SettingsDialog),
                matching: find.byType(TextField),
              ),
            )
            .toList();
        final [_, address, password] = fields();
        expect(address.keyboardType, TextInputType.url);
        expect(address.autofillHints, [AutofillHints.url]);
        // Without suggestions, Flutter on Android would mark it a visible password.
        expect(address.enableSuggestions, isTrue);
        await tester.tap(control('Paste a key'));
        await tester.pumpAndSettle();
        final [_, _, key] = fields();
        for (final secret in [password, key]) {
          expect(secret.enableSuggestions, isFalse);
          expect(secret.keyboardType, TextInputType.visiblePassword);
          expect(secret.autofillHints, isNull);
          expect(secret.enableIMEPersonalizedLearning, isFalse);
        }
      },
    );

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

    testWidgets('the panel beside the chat is named Documents', (tester) async {
      await pumpApp(tester, llm: planningServer());
      expect(inSources(find.text('Documents')), findsOneWidget);
      expect(
        inSources(find.text('Answers draw on the ones switched on.')),
        findsOneWidget,
      );
      expect(inSources(find.text('Sources')), findsNothing);
      expect(
        find.descendant(
          of: control('Documents, 2 on'),
          matching: find.text('2 on'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a file switched off fades only its type and is counted out', (
      tester,
    ) async {
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm);
      await tester.tap(find.byType(AppSwitch).first);
      await tester.pumpAndSettle();
      expect(h.sources.onCount, 1);
      expect(
        find.descendant(
          of: control('Documents, 1 on'),
          matching: find.text('1 on'),
        ),
        findsOneWidget,
      );
      expect(inSources(find.text('Not used · 120 words')), findsOneWidget);
      double opacityOf(Finder finder) => tester
          .widgetList<Opacity>(
            find.ancestor(of: finder, matching: find.byType(Opacity)),
          )
          .fold(1, (all, o) => all * o.opacity);
      expect(opacityOf(inSources(find.text('Q3 roadmap.pdf'))), 1);
      expect(opacityOf(inSources(find.text('PDF'))), 0.5);
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
      await tester.tap(control('Documents, 2 on'));
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
      expect(inSidebar('Not connected'), findsOneWidget);
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
      await tester.tap(control('Paste a key'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel('AnythingLLM developer API key').last,
        'K9',
      );
      await tester.tap(control('Save key'));
      await tester.pumpAndSettle();
      expect(h.store.saved?.apiKey, 'K9');
      expect(find.text('The key was saved.'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(inSidebar('Q3 planning'), findsOneWidget);
    });

    Future<Harness> signedIn(
      WidgetTester tester,
      FakeAnythingLlm llm,
      String password,
    ) async {
      final h = await pumpApp(tester, llm: llm, connection: null);
      h.shell.openSettings();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel('AnythingLLM server address').last,
        'https://owen.example.ts.net:3001',
      );
      await tester.enterText(
        find.bySemanticsLabel('Server password').last,
        password,
      );
      await tester.tap(control('Sign in'));
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('the address and password sign in and the workspaces load', (
      tester,
    ) async {
      final llm = planningServer()..auth = ServerAuth.password;
      final h = await signedIn(tester, llm, 'PASS-WORD');
      expect(h.store.saved?.baseUrl, 'https://owen.example.ts.net:3001');
      expect(h.store.saved?.apiKey, 'MADE-KEY');
      expect(h.store.saved?.password, 'PASS-WORD');
      expect(find.text('Signed in to owen.example.ts.net.'), findsOneWidget);
      expect(control('Sign in'), findsNothing);
      expect(inSidebar('Q3 planning'), findsOneWidget);
    });

    testWidgets('a wrong password says so and saves nothing', (tester) async {
      final llm = planningServer()..auth = ServerAuth.password;
      final h = await signedIn(tester, llm, 'WRONG');
      expect(h.store.saved, isNull);
      expect(
        find.text('The server did not accept the password.'),
        findsOneWidget,
      );
      expect(control('Sign in'), findsOneWidget);
    });

    testWidgets('an open server signs in with the address alone', (
      tester,
    ) async {
      final h = await signedIn(tester, planningServer(), '');
      expect(h.store.saved?.apiKey, 'MADE-KEY');
      expect(h.store.saved?.password, isNull);
    });

    testWidgets('a server with several users asks for a key', (tester) async {
      final llm = planningServer()..auth = ServerAuth.multiUser;
      final h = await signedIn(tester, llm, 'PASS-WORD');
      expect(h.store.saved, isNull);
      expect(find.textContaining('several users'), findsOneWidget);
      expect(
        find.bySemanticsLabel('AnythingLLM developer API key'),
        findsWidgets,
      );
      expect(control('Save key'), findsOneWidget);
      // A mistyped address can be put right: the password form comes back.
      await tester.tap(control('Use password'));
      await tester.pumpAndSettle();
      expect(control('Sign in'), findsOneWidget);
      expect(control('Save key'), findsNothing);
    });

    Future<Harness> connected(WidgetTester tester, FakeAnythingLlm llm) async {
      final h = await pumpApp(tester, llm: llm, connection: null);
      h.shell.openSettings();
      await tester.pumpAndSettle();
      await tester.tap(control('Paste a key'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel('AnythingLLM developer API key').last,
        'K9',
      );
      await tester.tap(control('Save key'));
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets(
      'a server with a password asks for it, and saves one it takes',
      (tester) async {
        final h = await connected(
          tester,
          planningServer()..auth = ServerAuth.password,
        );
        expect(find.text('Server password'), findsWidgets);
        await tester.enterText(
          find.bySemanticsLabel('Server password').last,
          'WRONG',
        );
        await tester.tap(control('Save password'));
        await tester.pumpAndSettle();
        expect(
          find.text('The server did not accept the password.'),
          findsOneWidget,
        );
        expect(h.store.saved?.password, isNull);
        await tester.enterText(
          find.bySemanticsLabel('Server password').last,
          'PASS-WORD',
        );
        await tester.tap(control('Save password'));
        await tester.pumpAndSettle();
        expect(h.store.saved?.password, 'PASS-WORD');
        expect(find.text('The password was saved.'), findsOneWidget);
        expect(control('Save password'), findsNothing);
        await tester.tap(control('Forget password'));
        await tester.pumpAndSettle();
        expect(h.store.saved?.password, isNull);
        expect(h.store.saved?.apiKey, 'K9');
      },
    );

    testWidgets('the password card fits the smallest window', (tester) async {
      final h = await pumpApp(
        tester,
        llm: planningServer()..auth = ServerAuth.password,
        size: const Size(360, 480),
      );
      await h.settings.connect('https://h:3001', 'K1');
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      final field = find.bySemanticsLabel('Server password').last;
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      expect(field, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an open server asks for no password', (tester) async {
      await connected(tester, planningServer());
      expect(find.text('Server password'), findsNothing);
    });

    testWidgets('a key the server refuses is not saved', (tester) async {
      final llm = planningServer()
        ..verifyError = const ApiException('The server rejected the key.');
      final h = await pumpApp(tester, llm: llm, connection: null);
      h.shell.openSettings();
      await tester.pumpAndSettle();
      await tester.tap(control('Paste a key'));
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
      await tester.tap(control('Edit connection'));
      await tester.pumpAndSettle();
      await tester.tap(control('Paste a key'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel('AnythingLLM developer API key').last,
        'K9',
      );
      await tester.tap(control('Save key'));
      await tester.pumpAndSettle();
      expect(h.store.saved?.apiKey, 'K9');
      expect(control('Save key'), findsNothing);
      expect(control('Edit connection'), findsOneWidget);
    });

    testWidgets('Forget asks once more, then deletes the key', (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      h.shell.openSettings();
      await tester.pumpAndSettle();
      await tester.tap(control('Forget this server'));
      await tester.pumpAndSettle();
      expect(control('Really forget it?'), findsOneWidget);
      await tester.tap(control('Really forget it?'));
      await tester.pumpAndSettle();
      expect(h.settings.configured, isFalse);
      expect(find.text('The saved key was deleted.'), findsOneWidget);
    });

    testWidgets('Back with the keyboard up only puts the keyboard away', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: planningServer());
      h.shell.openSettings();
      await tester.pumpAndSettle();
      await tester.tap(control('Edit connection'));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byType(SettingsDialog),
              matching: find.byType(EditableText),
            )
            .first,
      );
      raiseKeyboard(tester, 300);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.shell.settingsOpen, isTrue);
      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()),
      );
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.shell.settingsOpen, isFalse);
    });

    testWidgets('the QR code shows the connection only when asked', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: planningServer());
      h.shell.openSettings();
      await tester.pumpAndSettle();
      expect(find.byType(QrMark), findsNothing);
      await tester.tap(control('Connect a phone'));
      await tester.pumpAndSettle();
      final mark = tester.widget<QrMark>(find.byType(QrMark));
      expect(mark.data, pairingCode(sampleConnection));
      expect(find.text('Your phone cannot use this address'), findsNothing);
      await tester.tap(control('Hide the code'));
      await tester.pumpAndSettle();
      expect(find.byType(QrMark), findsNothing);
    });

    testWidgets('the QR code warns when the phone cannot use the address', (
      tester,
    ) async {
      final h = await pumpApp(
        tester,
        llm: planningServer(),
        connection: const Connection(
          baseUrl: 'http://localhost:3001',
          apiKey: 'K1',
        ),
      );
      h.shell.openSettings();
      await tester.pumpAndSettle();
      await tester.tap(control('Connect a phone'));
      await tester.pumpAndSettle();
      expect(find.text('Your phone cannot use this address'), findsOneWidget);
      expect(find.textContaining('is the phone itself'), findsOneWidget);
    });

    testWidgets('a scanned code connects as a typed key does', (tester) async {
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm, connection: null, canScan: true)
        ..scanCode = pairingCode(
          const Connection(
            baseUrl: 'https://owen.example.ts.net',
            apiKey: 'K9',
          ),
        );
      h.shell.openSettings();
      await tester.pumpAndSettle();
      await tester.tap(control('Scan QR code'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SettingsDialog),
          matching: find.byType(AppField),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Fake scan'));
      await tester.pumpAndSettle();
      expect(find.text('Fake scan'), findsNothing);
      expect(h.store.saved?.baseUrl, 'https://owen.example.ts.net');
      expect(h.store.saved?.apiKey, 'K9');
      expect(find.text('The key was saved.'), findsOneWidget);
      expect(inSidebar('Q3 planning'), findsOneWidget);
    });

    testWidgets('a scanned key the server refuses shows in the key field', (
      tester,
    ) async {
      final llm = planningServer()
        ..verifyError = const ApiException(
          'The server did not accept the key.',
        );
      final h = await pumpApp(tester, llm: llm, connection: null, canScan: true)
        ..scanCode = pairingCode(
          const Connection(
            baseUrl: 'https://owen.example.ts.net',
            apiKey: 'K9',
          ),
        );
      h.shell.openSettings();
      await tester.pumpAndSettle();
      await tester.tap(control('Scan QR code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fake scan'));
      await tester.pumpAndSettle();
      expect(h.store.saved, isNull);
      expect(find.text('The server did not accept the key.'), findsOneWidget);
      expect(control('Save key'), findsOneWidget);
      expect(find.text('K9'), findsOneWidget);
    });

    testWidgets('a code that is not a connection saves nothing', (
      tester,
    ) async {
      final h =
          await pumpApp(
              tester,
              llm: planningServer(),
              connection: null,
              canScan: true,
            )
            ..scanCode = 'https://example.com';
      h.shell.openSettings();
      await tester.pumpAndSettle();
      await tester.tap(control('Scan QR code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fake scan'));
      await tester.pumpAndSettle();
      expect(h.store.saved, isNull);
      expect(
        find.text('This QR code is not an AnywhereLLM connection.'),
        findsOneWidget,
      );
      expect(control('Sign in'), findsOneWidget);
    });

    testWidgets('Cancel closes the scanner', (tester) async {
      final h = await pumpApp(
        tester,
        llm: planningServer(),
        connection: null,
        canScan: true,
      );
      h.shell.openSettings();
      await tester.pumpAndSettle();
      await tester.tap(control('Scan QR code'));
      await tester.pumpAndSettle();
      await tester.tap(control('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Fake scan'), findsNothing);
      expect(control('Sign in'), findsOneWidget);
    });

    testWidgets('without a camera there is no Scan button', (tester) async {
      final h = await pumpApp(tester, llm: planningServer(), connection: null);
      h.shell.openSettings();
      await tester.pumpAndSettle();
      expect(control('Sign in'), findsOneWidget);
      expect(control('Scan QR code'), findsNothing);
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
    testWidgets(
      'a phone\'s chat header keeps 4 px at its left and 6 at its right',
      (tester) async {
        await pumpApp(
          tester,
          llm: planningServer(),
          size: const Size(390, 844),
        );
        final bar = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(PaneHeader),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(bar.padding, const EdgeInsets.only(left: 4, right: 6));
        // The workspace sits over the chat's name, and a pull down refreshes in place of a
        // button.
        expect(
          find.descendant(
            of: find.byType(PaneHeader),
            matching: find.text('Q3 planning'),
          ),
          findsOneWidget,
        );
        expect(find.byTooltip('Refresh'), findsNothing);
        // Documents shows its count alone where the header is narrow.
        expect(
          find.descendant(
            of: control('Documents, 2 on'),
            matching: find.text('2'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('on a phone, a pull down on the chat reads it again', (
      tester,
    ) async {
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm, size: const Size(390, 844));
      final reads = llm.calls.where((c) => c == 'workspaces').length;
      final list = find.byType(CustomScrollView).first;
      // A short pull does nothing; a long one, let go, refreshes.
      await tester.drag(list, const Offset(0, 30));
      await tester.pumpAndSettle();
      expect(llm.calls.where((c) => c == 'workspaces').length, reads);
      await tester.drag(list, const Offset(0, 1600));
      await tester.pumpAndSettle();
      expect(llm.calls.where((c) => c == 'workspaces').length, reads + 1);
      expect(h.chat.refreshing, isFalse);
    });

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
      await tester.tap(control('Documents, 2 on'));
      await tester.pumpAndSettle();
      expect(tester.getTopRight(find.byType(SourcesPanel)).dx, 1000);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.shell.sourcesOpen, isFalse);
    });

    testWidgets('on a phone, Documents is a sheet over the chat', (
      tester,
    ) async {
      final h = await pumpApp(
        tester,
        llm: planningServer(),
        size: const Size(390, 844),
        sourcesOpen: false,
      );
      expect(find.byType(SourcesPanel), findsNothing);
      await tester.tap(control('Documents, 2 on'));
      await tester.pumpAndSettle();
      final sheet = find.byType(SheetFrame);
      expect(
        find.descendant(of: sheet, matching: find.text('Documents')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Q3 roadmap.pdf')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      // The scrim above the sheet closes it, and so do Back and a drag down.
      await tester.tapAt(const Offset(195, 30));
      await tester.pumpAndSettle();
      expect(h.shell.sourcesOpen, isFalse);
      expect(find.byType(SheetFrame), findsNothing);
      await tester.tap(control('Documents, 2 on'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.shell.sourcesOpen, isFalse);
      await tester.tap(control('Documents, 2 on'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.descendant(of: sheet, matching: find.text('Documents')),
        const Offset(0, 300),
      );
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
