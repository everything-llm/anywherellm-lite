import 'dart:async';
import 'dart:ui' show Size;

import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/chat_log.dart';
import 'package:anywherellm/core/commands.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/embeds.dart';
import 'package:anywherellm/core/files.dart';
import 'package:anywherellm/core/outputs.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/core/upload.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/quick_switcher.dart';
import 'package:anywherellm/ui/sidebar.dart';
import 'package:anywherellm/ui/sources/sources_panel.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/widgets/drop_zone.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart' show EditableText, SingleChildScrollView;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
import '../support/pump.dart';

/// One width per shell layout, and the window's own minimum (see my_application.cc).
const sizes = [
  Size(1400, 900),
  Size(1000, 700),
  Size(780, 700),
  Size(500, 700),
  Size(360, 480),
];

const longWord =
    'an-extremely-long-unbroken-name-that-has-no-place-to-wrap-and-must-not-overflow-anything';

/// Data that stresses every layout: long unbroken names, a long chat and long files.
FakeAnythingLlm awkward() {
  final llm = FakeAnythingLlm();
  llm.spaces = [
    FakeWorkspace(
      'w',
      'name-$longWord',
      threads: [Thread(slug: 't', name: 'chat-$longWord')],
      docs: [libraryDoc(llm, 'file-$longWord.pdf', words: 123456)],
    ),
  ];
  llm.histories['t'] = [
    ChatMessage(role: Role.user, text: 'question-$longWord ' * 3),
    ChatMessage(
      role: Role.assistant,
      text: 'An answer that keeps going. ' * 40,
      citations: [
        Citation('file-$longWord.pdf'),
        Citation(
          'gone-$longWord.md',
          url: Uri.parse('https://example.com/$longWord/$longWord'),
        ),
      ],
    ),
    ChatMessage(
      role: Role.user,
      text: 'And these?',
      attachments: [SentFile('photo-$longWord.png')],
    ),
    ChatMessage(
      role: Role.assistant,
      text:
          '<think>reasoning-$longWord</think>'
          '## Heading-$longWord\n\n'
          '- item-$longWord\n\n'
          '```\nconst code = "$longWord-$longWord";\n```\n\n'
          '| Name | Value | Notes |\n|---|---|---|\n'
          '| $longWord | $longWord | $longWord |\n',
    ),
  ];
  return llm;
}

void main() {
  for (final size in sizes) {
    final at = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('a long chat fits at $at', (tester) async {
      await pumpApp(tester, llm: awkward(), size: size);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the open drawers and Settings fit at $at', (tester) async {
      final h = await pumpApp(tester, llm: awkward(), size: size);
      h.shell
        ..toggleSide()
        ..openSources();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      h.shell.openSettings();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('every Settings page fits at $at', (tester) async {
      final llm = awkward()
        ..chatLog = [
          LoggedChat(
            workspace: longWord,
            question: longWord,
            at: DateTime(2026, 10, 7),
          ),
        ]
        ..embedList = [
          Embed(
            uuid: 'e-$longWord',
            workspace: 'name-$longWord',
            mode: EmbedMode.query,
            enabled: true,
            chats: 123456,
          ),
        ];
      final h = await pumpApp(
        tester,
        llm: llm,
        size: size,
        canDictate: true,
        canSpeak: true,
      );
      h.shell.openSettings();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final page in SettingsPage.values) {
        h.shell.showSettingsPage(page);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: page.name);
        await tester.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: page.name);
      }
    });

    testWidgets('the QR code and the scanner fit at $at', (tester) async {
      final h = await pumpApp(
        tester,
        llm: awkward(),
        size: size,
        connection: const Connection(
          baseUrl: 'http://localhost:3001/$longWord',
          apiKey: 'K1',
        ),
        canScan: true,
      );
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      // A phone shows its code to no other phone.
      if (size.width >= 720) {
        await tester.ensureVisible(find.text('Connect a phone'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Connect a phone'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } else {
        expect(find.text('Connect a phone'), findsNothing);
      }
      await tester.ensureVisible(find.text('Edit connection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit connection'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      expect(find.text('Fake scan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the slash menu fits at $at', (tester) async {
      final llm = awkward()
        ..presets = [
          for (var i = 0; i < 8; i++)
            SlashCommand(
              command: '/cmd$i-$longWord',
              prompt: 'p',
              description: 'description-$longWord',
            ),
        ];
      await pumpApp(tester, llm: llm, size: size);
      await tester.enterText(composerField, '/');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the microphone and a dictation problem fit at $at', (
      tester,
    ) async {
      final h = await pumpApp(
        tester,
        llm: awkward(),
        size: size,
        canDictate: true,
      );
      h.dictation!.available = false;
      await tester.tap(
        find.byWidgetPredicate((w) => w is Tappable && w.label == 'Dictate'),
      );
      await tester.pump();
      expect(find.text('Could not listen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a search with long names fits at $at', (tester) async {
      final h = await pumpApp(tester, llm: awkward(), size: size);
      h.shell.toggleSide();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel('Search workspaces and chats').last,
        longWord.substring(0, 5),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the slash menu with its note fits at $at', (tester) async {
      final llm = awkward()
        ..errors['slashCommands'] = const ApiException('no', status: 401);
      await pumpApp(tester, llm: llm, size: size);
      await tester.enterText(composerField, '/');
      await tester.pump();
      expect(find.textContaining('has a password'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('adding a link or text in Sources fits at $at', (tester) async {
      final h = await pumpApp(tester, llm: awkward(), size: size);
      h.shell.openSources();
      await tester.pumpAndSettle();
      await tapVisible(tester, find.bySemanticsLabel('Paste text').last);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.bySemanticsLabel('Details').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final cancel = find.descendant(
        of: find.byType(SourcesPanel),
        matching: find.text('Cancel'),
      );
      await tester.ensureVisible(cancel);
      await tester.pumpAndSettle();
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.bySemanticsLabel('Add a link').last);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.bySemanticsLabel('Details').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tested question fits at $at', (tester) async {
      final h = await pumpApp(tester, llm: awkward(), size: size);
      h.shell.openSources();
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Test a question').last);
      await tester.pumpAndSettle();
      await h.sources.search('file-$longWord');
      await tester.pumpAndSettle();
      expect(h.sources.hits, isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('files waiting to be added fit at $at', (tester) async {
      final h = await pumpApp(tester, llm: awkward(), size: size);
      h.shell.openSources();
      await tester.pumpAndSettle();
      final zone = tester.widget<DropZone>(find.byType(DropZone).last);
      await zone.onFiles([
        for (final name in ['a-$longWord.pdf', 'b-$longWord.md'])
          UploadFile(name: name, read: () async => [1]),
      ]);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Details of a-$longWord.pdf'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renaming and deleting a workspace fit at $at', (tester) async {
      final h = await pumpApp(tester, llm: awkward(), size: size);
      h.shell.toggleSide();
      await tester.pumpAndSettle();
      await tester.tap(switcher);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Rename workspace').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await fromMenu(tester, 'Delete workspace…');
      expect(find.bySemanticsLabel('Cancel'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an agent answer fits at $at', (tester) async {
      final llm = awkward()..hold = true;
      final h = await pumpApp(tester, llm: llm, size: size);
      h.chat.newChat();
      await tester.pumpAndSettle();
      await h.chat.send('news');
      llm.chat!.add(StatusChunk('Using SearXNG to search for $longWord'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      llm.chat!
        ..add(const WholeAnswer('Headline'))
        ..add(
          ChatDone([
            for (var i = 0; i < 9; i++)
              Citation(
                'story-$i-$longWord',
                url: Uri.parse('https://example.com/$longWord'),
              ),
          ]),
        );
      await llm.chat!.close();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the browser, its chip and its panel fit at $at', (
      tester,
    ) async {
      final llm = awkward()..hold = true;
      llm.histories['t']!.add(
        ChatMessage(
          role: Role.assistant,
          text:
              'Card: [![Browser: https://example.com/$longWord]'
              '(https://h:8445/_live/browser/bw-3aeecef2b460eeb7.jpg)]'
              '(https://h:8445/_live/browser/bw-3aeecef2b460eeb7)',
        ),
      );
      final h = await pumpApp(tester, llm: llm, size: size);
      await h.chat.send('again');
      llm.chat!.add(
        StatusChunk('Looking for "$longWord"', tool: 'browser-read'),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      h.shell.showBrowser();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      llm.chat!
        ..add(const WholeAnswer('Found it.'))
        ..add(const ChatDone([]));
      await llm.chat!.close();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('an answer\'s More menu and its details fit at $at', (
      tester,
    ) async {
      final llm = awkward()
        ..measured = AnswerMetrics(
          model: 'model-$longWord',
          tokens: 1642,
          seconds: 73.852,
          speed: 22.2,
          cost: 0.0049,
        );
      final h = await pumpApp(
        tester,
        llm: llm,
        size: size,
        prefsStore: FakePrefsStore(
          const Prefs().withSwitch(ChatSwitch.answerDetails, true),
        ),
      );
      await h.chat.send('measured');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tapVisible(
        tester,
        find.bySemanticsLabel(
          'More for this answer: model, time, tokens, speed and cost',
        ),
      );
      await tester.pumpAndSettle();
      // A menu on a desktop, a sheet titled in sentence case on a phone.
      expect(
        find.text(size.width < 720 ? 'This answer' : 'THIS ANSWER'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a message refused as the chat answers fits at $at', (
      tester,
    ) async {
      final llm = awkward();
      final h = await pumpApp(tester, llm: llm, size: size);
      final events = StreamController<ChatEvent>();
      addTearDown(() => unawaited(events.close()));
      llm
        ..running['t'] = (question: 'phone-$longWord', events: events)
        ..errors['streamChat'] = const AlreadyAnswering('Busy.');
      await h.chat.send('question-$longWord');
      // The answer streams, and its caret never settles.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('maybe on another device'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an app beside the chat, or in its sheet, fits at $at', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: awkward(), size: size);
      h.shell.showApp(
        appCardOf(
          Uri.parse('https://h:8455/_live/apps/w/$longWord.png'),
          Uri.parse('https://h:8447/w/apps/$longWord/'),
          'app-$longWord',
          Uri.parse('https://h:3001'),
        )!,
      );
      await tester.pumpAndSettle();
      expect(find.text('app-$longWord'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Ctrl K switcher fits at $at', (tester) async {
      final h = await pumpApp(tester, llm: awkward(), size: size);
      h.shell.toggleSwitcher();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.descendant(
          of: find.byType(QuickSwitcher),
          matching: find.byType(EditableText),
        ),
        'an-extremely',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(QuickSwitcher), findsOneWidget);
    });

    testWidgets('a draft and the no-key banner fit at $at', (tester) async {
      final h = await pumpApp(tester, llm: awkward(), size: size);
      h.chat.newChat();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await h.settings.clear();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in sizes) {
    final at = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('the workspace\'s pages fit at $at', skip: size.width >= 720, (
      tester,
    ) async {
      final llm = awkward();
      llm.spaces.first.prompt = 'prompt-$longWord';
      final h = await pumpApp(tester, llm: llm, size: size);
      h.shell.showPane(Pane.files);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final page in [
        FilesSection.documents,
        FilesSection.instructions,
        FilesSection.answers,
      ]) {
        h.shell.showWorkspacePage(page);
        await h.files.openSection(page);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$page');
      }
      await tester.tap(find.text('Chat model').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // A phone shows the workspace's pages, with no tree.
    testWidgets(
      'Files and each kind of node fit at $at',
      skip: size.width < 720,
      (tester) async {
        final llm = awkward();
        llm.spaces.first.prompt = 'prompt-$longWord';
        final h = await pumpApp(tester, llm: llm, size: size);
        h.shell
          ..showPane(Pane.files)
          ..toggleSide();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final path in [
          '/workspaces/w',
          '/workspaces/w/docs',
          '/workspaces/w/chats',
          '/library/custom-documents',
        ]) {
          h.files.toggle(path);
        }
        for (final path in [
          '/workspaces/w',
          '/workspaces/w/docs',
          '/workspaces/w/PROMPT.md',
          '/workspaces/w/settings.json',
          '/workspaces/w/chats/t',
          '/workspaces/w/docs/custom-documents/file-$longWord.pdf.json',
          '/library',
          '/library/custom-documents',
          '/library/custom-documents/file-$longWord.pdf.json',
          '/keys',
        ]) {
          await h.files.select(path);
          await tester.pumpAndSettle();
          expect(h.files.node, isNotNull, reason: path);
          expect(tester.takeException(), isNull, reason: path);
        }
        h.shell.closeSide();
        await h.files.select('/library/custom-documents');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Delete folder…'));
        await tester.tap(find.text('Delete folder…'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Cancel'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in sizes) {
    final at = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('Files\' Essentials and each section fit at $at', (
      tester,
    ) async {
      final llm = awkward();
      final path = 'custom-documents/file-$longWord.pdf.json';
      await llm.pinDocument('w', path, pinned: true);
      final h = await pumpApp(tester, llm: llm, size: size);
      h.shell
        ..showPane(Pane.files)
        ..toggleSide();
      await tester.pumpAndSettle();
      expect(h.files.essentials, isTrue);
      expect(tester.takeException(), isNull);
      for (final section in FilesSection.values) {
        await h.files.openSection(section);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: section.name);
      }
      h.shell.closeSide();
      await h.files.openSection(FilesSection.documents);
      await tester.pumpAndSettle();
      await h.sources.toggle(h.sources.files.first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await h.files.viewText(path, 'file-$longWord.pdf');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in const [Size(360, 640), Size(1000, 700)]) {
    testWidgets('clear of a phone\'s bars at ${size.width.toInt()} wide', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.resetPadding);
      final h = await pumpApp(tester, llm: awkward(), size: size);
      h.shell
        ..toggleSide()
        ..openSources();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final top = tester.getTopLeft(find.byType(Sidebar)).dy;
      expect(top, greaterThanOrEqualTo(24));
    });
  }

  testWidgets('resizing through every layout keeps working', (tester) async {
    final h = await pumpApp(tester, llm: awkward(), size: sizes.first);
    for (final size in [...sizes, ...sizes.reversed]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'at ${size.width}');
    }
    expect(h.chat.activeThread, 't');
  });
}
