import 'dart:async';
import 'dart:convert';

import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/ui/chat/chat_view.dart';
import 'package:anywherellm/ui/chat/wait_line.dart';
import 'package:anywherellm/ui/settings/settings_dialog.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/home.dart';
import 'package:anywherellm/ui/shelf.dart';
import 'package:anywherellm/ui/sources/sources_panel.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/widgets/controls.dart';
import 'package:anywherellm/ui/widgets/sheet.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// [text] in the Chats tab, drawn while Settings is closed.
Finder inHome(String text) =>
    find.descendant(of: find.byType(ChatsTab), matching: find.text(text));

Finder inSources(Finder finder) =>
    find.descendant(of: find.byType(SourcesPanel), matching: finder);

Finder inChat(Finder finder) =>
    find.descendant(of: find.byType(ChatView), matching: finder);

Finder get message => find.bySemanticsLabel('Message');

/// The app with Documents open over the chat.
Future<Harness> withDocuments(WidgetTester tester, FakeAnythingLlm llm) async {
  final h = await pumpApp(tester, llm: llm);
  h.shell.openSources();
  await tester.pumpAndSettle();
  return h;
}

/// The server's address in Settings: the first run's field or the one that edits a saved one.
Finder get addressField =>
    find.bySemanticsLabel(RegExp(r'^(AnythingLLM s|S)erver address$')).last;

void main() {
  group('the chat', () {
    testWidgets('says when the saved server does not answer', (tester) async {
      final llm = planningServer()
        ..errors['workspaces'] = const ApiException(
          'Could not reach the server.',
        );
      final h = await pumpApp(tester, llm: llm);
      h.shell.openSettings();
      await tester.pumpAndSettle();
      expect(find.text('Connection problem'), findsOneWidget);
      expect(find.text('Connected'), findsNothing);
    });

    testWidgets('a workspace with no chats invites a first question', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: planningServer());
      await h.chat.select('household');
      await tester.pumpAndSettle();
      expect(
        find.text('Ask about Household.', findRichText: true),
        findsOneWidget,
      );
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
        expect(find.byType(WaitLine), findsOneWidget);
        expect(find.byType(Caret), findsNothing);
        expect(control('Stop the answer'), findsOneWidget);

        llm.chat!.add(const TextChunk('The roadmap.'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(Caret), findsOneWidget);
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

    testWidgets('on a phone a citation opens the passages read from its file', (
      tester,
    ) async {
      final llm = planningServer()..hold = true;
      final h = await pumpApp(tester, llm: llm);
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
      expect(
        find.textContaining(' · 2 passages, closest first'),
        findsOneWidget,
      );
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
      expect(find.byType(WaitLine), findsOneWidget);
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
        h.shell.openSources();
        await tester.pumpAndSettle();
        await tester.tap(find.byType(AppSwitch).first);
        h.shell.closeSources();
        await tester.pumpAndSettle();
        expect(control('Summarise Customer interviews'), findsOneWidget);
        expect(control('Summarise Q3 roadmap'), findsNothing);
      },
    );

    testWidgets(
      'a long document is named short in a suggestion and whole in the message',
      (tester) async {
        const title =
            'Evidence-Based Gamification Design: What Works, When, and Why.pdf';
        final llm = planningServer();
        llm.spaces.first.docs.insert(0, libraryDoc(llm, title));
        final h = await pumpApp(tester, llm: llm, size: const Size(360, 720));
        h.chat.newChat();
        await tester.pumpAndSettle();
        expect(control('Compare the first two documents'), findsOneWidget);
        await tester.tap(
          control('Summarise Evidence-Based Gamification Design'),
        );
        await tester.pump();
        expect(
          tester.widget<EditableText>(composerField).controller.text,
          'Summarise Evidence-Based Gamification Design: What Works, When, and Why',
        );
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

    testWidgets(
      'the server address is a web address, and the key is left out of autofill',
      (tester) async {
        final h = await pumpApp(
          tester,
          llm: planningServer(),
          connection: null,
        );
        h.shell.openSettings(SettingsPage.connection);
        await tester.pumpAndSettle();
        List<TextField> fields() => tester
            .widgetList<TextField>(
              find.descendant(
                of: find.byType(SettingsDialog),
                matching: find.byType(TextField),
              ),
            )
            .toList();
        final [address, key] = fields();
        expect(address.keyboardType, TextInputType.url);
        expect(address.autofillHints, [AutofillHints.url]);
        // Without suggestions, Flutter on Android would mark it a visible password.
        expect(address.enableSuggestions, isTrue);
        expect(key.enableSuggestions, isFalse);
        expect(key.keyboardType, TextInputType.visiblePassword);
        expect(key.autofillHints, isNull);
        expect(key.enableIMEPersonalizedLearning, isFalse);
      },
    );

    testWidgets(
      'until its first words an answer says what it waits on, and past 10 s for how long',
      (tester) async {
        final llm = planningServer()..hold = true;
        llm.spaces[0].settings['chatModel'] = 'glm-5.3';
        await pumpApp(tester, llm: llm);
        await typeAndEnter(tester, 'What is due?');
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Asking glm-5.3…'), findsOneWidget);
        expect(find.textContaining(' s'), findsNothing);

        llm.chat!.add(const StatusChunk('Running web-browsing'));
        await tester.pump(const Duration(seconds: 11));
        expect(find.text('Running web-browsing'), findsOneWidget);
        expect(find.text('Asking glm-5.3…'), findsNothing);
        expect(find.text(' · 11 s'), findsOneWidget);
        expect(find.byType(Caret), findsNothing);

        llm.chat!.add(const TextChunk('The roadmap.'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(WaitLine), findsNothing);
        expect(find.byType(Caret), findsOneWidget);
        expect(find.text('Running web-browsing'), findsOneWidget);
        llm.chat!.add(const ChatDone([]));
        await llm.chat!.close();
        await tester.pumpAndSettle();
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
        // Three by name in one line, the rest behind +6, which lists them all in a sheet.
        expect(control('Source 3: Story 3'), findsOneWidget);
        expect(control('Source 4: Story 4'), findsNothing);
        await tester.tap(control('6 more sources'));
        await tester.pumpAndSettle();
        expect(h.shell.citedOpen, isTrue);
        expect(find.text('Sources'), findsOneWidget);
        expect(find.text('9 sources'), findsOneWidget);
        expect(control('Story 9'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(h.shell.citedOpen, isFalse);
      },
    );

    testWidgets('the sheet over the chat is named Documents', (tester) async {
      await withDocuments(tester, planningServer());
      expect(inSources(find.text('Documents')), findsOneWidget);
      expect(
        inSources(find.text('Answers draw on the ones switched on.')),
        findsOneWidget,
      );
      expect(inSources(find.text('Sources')), findsNothing);
      expect(find.text('Q3 planning · 2 docs in use'), findsOneWidget);
    });

    testWidgets('a file switched off fades only its type and is counted out', (
      tester,
    ) async {
      final llm = planningServer();
      final h = await withDocuments(tester, llm);
      await tester.tap(find.byType(AppSwitch).first);
      await tester.pumpAndSettle();
      expect(h.sources.onCount, 1);
      expect(find.text('Q3 planning · 1 doc in use'), findsOneWidget);
      expect(inSources(find.text('Not used · 120 words')), findsOneWidget);
      double opacityOf(Finder finder) => tester
          .widgetList<Opacity>(
            find.ancestor(of: finder, matching: find.byType(Opacity)),
          )
          .fold(1, (all, o) => all * o.opacity);
      expect(opacityOf(inSources(find.text('Q3 roadmap.pdf'))), 1);
      expect(opacityOf(inSources(find.text('PDF'))), 0.5);
    });

    testWidgets(
      'a file opens its text, which removes it, and the sheet comes back',
      (tester) async {
        final llm = planningServer();
        final h = await withDocuments(tester, llm);
        await tester.tap(control('View extracted text of Q3 roadmap.pdf'));
        await tester.pumpAndSettle();
        expect(h.shell.sourcesOpen, isFalse);
        expect(h.files.reading?.title, 'Q3 roadmap.pdf');
        await tapVisible(tester, control('Remove from workspace'));
        await tester.pumpAndSettle();
        // Its undo is in the sheet, which comes back over what showed under it.
        expect(h.shell.sourcesOpen, isTrue);
        expect(h.shell.pane, Pane.chats);
        expect(find.text('Removed Q3 roadmap.pdf'), findsOneWidget);
        await tester.tap(control('Undo'));
        await tester.pumpAndSettle();
        expect(h.sources.files, hasLength(2));
        expect(find.text('Removed Q3 roadmap.pdf'), findsNothing);
      },
    );

    testWidgets('a file\'s download saves the text the server read', (
      tester,
    ) async {
      final h = await withDocuments(tester, planningServer());
      await tester.tap(control('View extracted text of Q3 roadmap.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(control('Download the extracted text'));
      await tester.pumpAndSettle();
      expect(
        utf8.decode(h.saved['Q3 roadmap.pdf.txt']!),
        'The text of Q3 roadmap.pdf.',
      );
    });

    testWidgets('a file whose text cannot be read says why', (tester) async {
      final llm = planningServer()
        ..errors['document'] = const ApiException('The server is down.');
      final h = await withDocuments(tester, llm);
      await tester.tap(control('View extracted text of Q3 roadmap.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(control('Download the extracted text'));
      await tester.pumpAndSettle();
      expect(h.saved, isEmpty);
      // Back gives the sheet back, which says why.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        inSources(find.text('Could not save Q3 roadmap.pdf')),
        findsOneWidget,
      );
      expect(inSources(find.text('The server is down.')), findsOneWidget);
    });
  });

  group('the bar of tabs', () {
    Finder tab(String label) =>
        find.descendant(of: find.byType(HomeTabBar), matching: control(label));

    testWidgets('stays under the chat, and its Chats tab puts the shelf away', (
      tester,
    ) async {
      final h = await pumpApp(tester);
      expect(find.byType(HomeTabBar), findsOneWidget);
      // The composer sits above the bar, not under it.
      expect(
        tester.getBottomLeft(find.byType(ChatView)).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(HomeTabBar)).dy),
      );

      h.shell.openShelf();
      await tester.pumpAndSettle();
      expect(find.byType(ChatsShelf), findsOneWidget);
      await tester.tap(tab('Chats'));
      await tester.pumpAndSettle();
      expect(h.shell.shelfOpen, isFalse);
      expect(find.byType(HomeTabBar), findsOneWidget);
    });

    testWidgets('stays under Settings\' pages and Upcoming', (tester) async {
      final h = await pumpApp(tester, shelf: true);
      h.shell.openSettings(SettingsPage.appearance);
      await tester.pumpAndSettle();
      expect(find.byType(HomeTabBar), findsOneWidget);
      expect(h.shell.tab, HomeTab.settings);

      await tester.tap(tab('Chats'));
      await tester.pumpAndSettle();
      h.shell.openToolkitPage(ToolkitPage.upcoming);
      await tester.pumpAndSettle();
      expect(find.byType(HomeTabBar), findsOneWidget);
    });

    testWidgets('gives way to the keyboard', (tester) async {
      await pumpApp(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.byType(HomeTabBar), findsNothing);

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.byType(HomeTabBar), findsOneWidget);
    });

    testWidgets('is not on the first run\'s welcome', (tester) async {
      final h = await pumpApp(tester, connection: null, shelf: true);
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      expect(find.byType(HomeTabBar), findsNothing);
    });

    testWidgets('a sheet covers it', (tester) async {
      final h = await pumpApp(tester);
      h.shell.openSources();
      await tester.pumpAndSettle();
      // The sheet lies over the bar, so its Chats tab cannot be reached.
      await tester.tapAt(
        tester.getCenter(tab('Chats')),
        kind: PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();
    });
  });

  group('Settings', () {
    testWidgets('with no key, the composer sends the person to Settings', (
      tester,
    ) async {
      final h = await pumpApp(tester, connection: null);
      expect(find.text('Welcome to AnywhereLLM'), findsOneWidget);
      await tapVisible(tester, control('Open Settings'));
      await tester.pumpAndSettle();
      expect(h.shell.settingsOpen, isTrue);
      expect(h.shell.settingsPage, SettingsPage.connection);
      expect(control('Connect'), findsOneWidget);
    });

    testWidgets('a key the server takes is saved and the workspaces load', (
      tester,
    ) async {
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm, connection: null);
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      await tester.enterText(addressField, 'https://h:3001');
      await tester.enterText(
        find.bySemanticsLabel('AnythingLLM developer API key').last,
        'K9',
      );
      await tapVisible(tester, control('Connect'));
      await tester.pumpAndSettle();
      expect(h.store.saved?.apiKey, 'K9');
      expect(find.text('The key was saved.'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      h.shell
        ..openChat()
        ..openShelf();
      await tester.pumpAndSettle();
      expect(inHome('Q3 planning'), findsOneWidget);
    });

    testWidgets('a key the server refuses is not saved', (tester) async {
      final llm = planningServer()
        ..verifyError = const ApiException('The server rejected the key.');
      final h = await pumpApp(tester, llm: llm, connection: null);
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      await tester.enterText(addressField, 'https://h:3001');
      await tester.enterText(
        find.bySemanticsLabel('AnythingLLM developer API key').last,
        'WRONG',
      );
      await tapVisible(tester, control('Connect'));
      await tester.pumpAndSettle();
      expect(h.store.saved, isNull);
      expect(find.text('The server rejected the key.'), findsOneWidget);
      expect(control('Connect'), findsOneWidget);
    });

    testWidgets('a replaced key closes the form once saved', (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      await tapVisible(tester, control('Edit connection'));
      await tester.pumpAndSettle();
      await tester.enterText(addressField, 'https://h:3001');
      await tester.enterText(
        find.bySemanticsLabel('AnythingLLM developer API key').last,
        'K9',
      );
      await tapVisible(tester, control('Save key'));
      await tester.pumpAndSettle();
      expect(h.store.saved?.apiKey, 'K9');
      expect(control('Save key'), findsNothing);
      expect(control('Edit connection'), findsOneWidget);
    });

    testWidgets('Forget asks once more, then deletes the key', (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      await tapVisible(tester, control('Forget this server'));
      await tester.pumpAndSettle();
      expect(control('Really forget it?'), findsOneWidget);
      await tapVisible(tester, control('Really forget it?'));
      await tester.pumpAndSettle();
      expect(h.settings.configured, isFalse);
      expect(find.text('The saved key was deleted.'), findsOneWidget);
    });

    testWidgets('Back with the keyboard up only puts the keyboard away', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: planningServer());
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      await tapVisible(tester, control('Edit connection'));
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
      // Back from a page opened over the chat gives the chat back.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.shell.settingsOpen, isFalse);
    });

    testWidgets('a scanned code connects as a typed key does', (tester) async {
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm, connection: null, canScan: true)
        ..scanCode =
            'anywherellm://connect?url=https%3A%2F%2Fowen.example.ts.net&key=K9';
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      await tapVisible(tester, control('Scan QR code'));
      await tester.pumpAndSettle();
      expect(h.shell.scanning, isTrue);
      await tester.tap(find.text('Fake scan'));
      await tester.pumpAndSettle();
      expect(find.text('Fake scan'), findsNothing);
      expect(h.store.saved?.baseUrl, 'https://owen.example.ts.net');
      expect(h.store.saved?.apiKey, 'K9');
      expect(find.text('The key was saved.'), findsOneWidget);
      h.shell
        ..openChat()
        ..openShelf();
      await tester.pumpAndSettle();
      expect(inHome('Q3 planning'), findsOneWidget);
    });

    testWidgets('a scanned key the server refuses shows in the key field', (
      tester,
    ) async {
      final llm = planningServer()
        ..verifyError = const ApiException(
          'The server did not accept the key.',
        );
      final h = await pumpApp(tester, llm: llm, connection: null, canScan: true)
        ..scanCode =
            'anywherellm://connect?url=https%3A%2F%2Fowen.example.ts.net&key=K9';
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      await tapVisible(tester, control('Scan QR code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fake scan'));
      await tester.pumpAndSettle();
      expect(h.store.saved, isNull);
      expect(find.text('The server did not accept the key.'), findsOneWidget);
      expect(control('Connect'), findsOneWidget);
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
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      await tapVisible(tester, control('Scan QR code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fake scan'));
      await tester.pumpAndSettle();
      expect(h.store.saved, isNull);
      expect(
        find.text('This QR code is not an AnywhereLLM connection.'),
        findsOneWidget,
      );
      expect(control('Connect'), findsOneWidget);
    });

    testWidgets('Cancel closes the scanner', (tester) async {
      final h = await pumpApp(
        tester,
        llm: planningServer(),
        connection: null,
        canScan: true,
      );
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      await tapVisible(tester, control('Scan QR code'));
      await tester.pumpAndSettle();
      await tapVisible(tester, control('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Fake scan'), findsNothing);
      expect(control('Connect'), findsOneWidget);
    });

    testWidgets('without a camera there is no Scan button', (tester) async {
      final h = await pumpApp(tester, llm: planningServer(), connection: null);
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      expect(control('Connect'), findsOneWidget);
      expect(control('Scan QR code'), findsNothing);
    });

    testWidgets('Esc and the back arrow step out of it', (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      h.shell.openSettings();
      await tester.pumpAndSettle();
      await tester.tap(control('Connection'));
      await tester.pumpAndSettle();
      expect(h.shell.settingsPage, SettingsPage.connection);
      // A page opened from the list steps back to it, and the list back to the Chats tab.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.shell.settingsPage, isNull);
      expect(h.shell.settingsOpen, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsNothing);
      h.shell
        ..openSettings()
        ..showSettingsPage(SettingsPage.chat);
      await tester.pumpAndSettle();
      await tester.tap(control('Back to Settings'));
      await tester.pumpAndSettle();
      expect(h.shell.settingsPage, isNull);
    });
  });

  group('a narrow window', () {
    testWidgets(
      'a phone\'s chat header names the workspace and its documents over the chat',
      (tester) async {
        final h = await pumpApp(tester, llm: planningServer());
        expect(find.text('Q3 planning · 2 docs in use'), findsOneWidget);
        // A pull down refreshes, and Documents is under the workspace's settings.
        expect(find.byTooltip('Refresh'), findsNothing);
        expect(control('Documents, 2 on'), findsNothing);
        expect(find.byTooltip('New chat'), findsOneWidget);
        // On a saved chat the title opens the chat's sheet.
        await tester.tap(find.text('Q3 planning · 2 docs in use'));
        await tester.pumpAndSettle();
        expect(h.shell.chatSheet, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('on a phone, a pull down on the chat reads it again', (
      tester,
    ) async {
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm);
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

    testWidgets('on a phone, Documents is a sheet over the chat', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: planningServer());
      expect(find.byType(SourcesPanel), findsNothing);
      h.shell.openSources();
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
      h.shell.openSources();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.shell.sourcesOpen, isFalse);
      h.shell.openSources();
      await tester.pumpAndSettle();
      await tester.drag(
        find.descendant(of: sheet, matching: find.text('Documents')),
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();
      expect(h.shell.sourcesOpen, isFalse);
    });
  });
}
