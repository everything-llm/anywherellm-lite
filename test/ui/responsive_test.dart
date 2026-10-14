import 'dart:ui' show Offset, Size;

import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/chat_log.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/embeds.dart';
import 'package:anywherellm/core/files.dart';
import 'package:anywherellm/core/outputs.dart';
import 'package:anywherellm/core/activity.dart';
import 'package:anywherellm/core/library.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/settings/memory_page.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/settings/walkthrough.dart';
import 'package:anywherellm/ui/files/workspace_pages.dart';
import 'package:anywherellm/ui/home.dart';
import 'package:anywherellm/ui/sources/sources_panel.dart';
import 'package:anywherellm/ui/activity.dart' show ActivityOpen;
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/task_sheet.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:anywherellm/ui/workspace_sheets.dart';
import 'package:flutter/material.dart' show AxisDirection, Scrollable;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
import '../support/fake_toolkit.dart';
import '../support/picker.dart';
import '../support/pump.dart';

/// A large phone, a small one, a phone on its side, and a short window.
const sizes = [Size(412, 915), Size(360, 640), Size(740, 360), Size(360, 480)];

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

/// Each size at normal text, and the small phones at the system's largest, 200%, since a fixed
/// height is the first thing large text breaks.
final cases = [
  for (final size in sizes) (size, 1.0),
  (sizes[1], 2.0),
  (sizes[3], 2.0),
];

/// Scales the text for the tests of a group, then puts it back.
void textScaledTo(double scale) {
  if (scale == 1.0) return;
  setUp(() {
    final dispatcher =
        TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
    dispatcher.textScaleFactorTestValue = scale;
    addTearDown(dispatcher.clearTextScaleFactorTestValue);
  });
}

void main() {
  for (final (size, scale) in cases) {
    final at =
        '${size.width.toInt()}x${size.height.toInt()}'
        '${scale == 1.0 ? '' : ' at ${(scale * 100).toInt()}% text'}';
    group(at, () {
      textScaledTo(scale);

      testWidgets('a long chat fits', (tester) async {
        await pumpApp(tester, llm: awkward(), size: size);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the Chats tab, the sheet and Settings fit', (tester) async {
        final h = await pumpApp(tester, llm: awkward(), size: size);
        h.shell.closeChat();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        h.shell.openSources();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        h.shell.openSettings();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('every Settings page fits', (tester) async {
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
          toolkitServer: FakeToolkit(),
        );
        h.shell.openSettings();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final page in SettingsPage.values) {
          h.shell.showSettingsPage(page);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: page.name);
          await tester.drag(
            find
                .byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                )
                .last,
            const Offset(0, -2000),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: page.name);
        }
        h.shell
          ..showSettingsPage(SettingsPage.memory)
          ..togglePopup(const MemorySheet(global: true));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'a new memory');
      });

      testWidgets('the scanner fits', (tester) async {
        final h = await pumpApp(
          tester,
          llm: awkward(),
          size: size,
          connection: const Connection(
            baseUrl: 'https://localhost:3001/$longWord',
            apiKey: 'K1',
          ),
          canScan: true,
        );
        h.shell.openSettings(SettingsPage.connection);
        await tester.pumpAndSettle();
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

      testWidgets('the microphone and a dictation problem fit', (tester) async {
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

      testWidgets('a search with long names fits', (tester) async {
        await pumpApp(tester, llm: awkward(), size: size, onChat: false);
        await tester.enterText(
          find.bySemanticsLabel('Search workspaces and chats').last,
          longWord.substring(0, 5),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('adding a link or text in Sources fits', (tester) async {
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

      testWidgets('a tested question fits', (tester) async {
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

      testWidgets('files waiting to be added fit', (tester) async {
        final h = await pumpApp(tester, llm: awkward(), size: size);
        h.shell.openSources();
        await tester.pumpAndSettle();
        FilePickerPlatform.instance = FakePicker([
          Picked('a-$longWord.pdf'),
          Picked('b-$longWord.md'),
        ]);
        await tapVisible(
          tester,
          find.descendant(
            of: find.byType(SourcesPanel),
            matching: control('Add a file'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Details of a-$longWord.pdf'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('making, renaming and deleting a workspace fit', (
        tester,
      ) async {
        final h = await pumpApp(tester, llm: awkward(), size: size);
        // New workspace, with long instructions typed.
        {
          h.shell.togglePopup(WorkspaceSheet.create);
          await tester.pumpAndSettle();
          await tester.enterText(
            typingField(find.byType(WorkspaceSheetView)).last,
            'instructions-$longWord\n' * 12,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
        // Rename and delete are in the workspace's settings, in sheets.
        {
          h.shell.showPane(Pane.files);
          await tester.pumpAndSettle();
          await tapVisible(tester, control('Rename'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            control('Delete workspace'),
            200,
            scrollable: find
                .descendant(
                  of: find.byType(WorkspacePages),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tapVisible(tester, control('Delete workspace'));
          await tester.pumpAndSettle();
          expect(control('Keep'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      });

      testWidgets('an agent answer fits', (tester) async {
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

      testWidgets('an answer\'s More menu and its details fit', (tester) async {
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
        expect(find.text('This answer'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a draft and the no-key banner fit', (tester) async {
        final h = await pumpApp(tester, llm: awkward(), size: size);
        h.chat.newChat();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await h.settings.clear();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        h.shell.openSettings(SettingsPage.connection);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'the first run');
      });

      testWidgets('each screen of How connecting works fits', (tester) async {
        final h = await pumpApp(
          tester,
          connection: null,
          size: size,
          canScan: true,
        );
        h.shell
          ..openSettings(SettingsPage.connection)
          ..showGuide(Guide.connect);
        await tester.pumpAndSettle();
        for (var n = 0; n < connectSteps.length; n++) {
          expect(
            find.text('${n + 1} of ${connectSteps.length}'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull, reason: 'screen ${n + 1}');
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
        }
      });

      testWidgets('Upcoming, a task and the New task form fit', (tester) async {
        final toolkit = FakeToolkit()
          ..served = {
            ToolkitFeature.memories,
            ToolkitFeature.jobs,
            ToolkitFeature.jobsWrite,
          }
          ..jobs = [
            ScheduledJob(
              id: '1',
              name: 'job-$longWord',
              prompt: 'prompt-$longWord ' * 8,
              cron: '0 7 * * 1',
              workspace: 'name-$longWord',
              workspaceSlug: 'w',
              lastStatus: 'failed',
              lastRun: DateTime.now().toUtc(),
            ),
          ]
          ..runRecords['1'] = [
            for (var n = 0; n < 5; n++)
              JobRun(
                startedAt: DateTime.now().toUtc(),
                status: n == 0 ? 'failed' : 'completed',
                result: 'result-$longWord',
              ),
          ];
        final h = await pumpApp(
          tester,
          llm: awkward(),
          toolkitServer: toolkit,
          size: size,
          onChat: false,
        );
        h.shell.openToolkitPage(ToolkitPage.upcoming);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'the page');
        h.shell.togglePopup(const TaskSheet(id: '1'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'the task');
        h.shell.togglePopup(const TaskSheet(id: '1', editing: true));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'the form');
        h.shell.togglePopup(const TaskSheet());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'the new task');
      });

      testWidgets('Library and Activity fit, with long names', (tester) async {
        final toolkit = FakeToolkit()
          ..served = {
            ToolkitFeature.memories,
            ToolkitFeature.jobs,
            ToolkitFeature.library,
            ToolkitFeature.activity,
          }
          ..libraryContents = LibraryContents(
            apps: [
              LibraryApp(
                title: 'app-$longWord',
                page: '/apps-lean/x.html',
                workspace: 'name-$longWord',
                workspaceSlug: 'w',
                change: 'change-$longWord',
                changed: DateTime.now().toUtc(),
              ),
            ],
            files: [
              LibraryFile(
                file: GeneratedFile(
                  type: 'PdfFileDownload',
                  name: 'file-$longWord.pdf',
                  storageName: 'pdf-1.pdf',
                  size: 123456,
                ),
                workspace: 'name-$longWord',
                workspaceSlug: 'w',
                created: DateTime.now().toUtc(),
              ),
            ],
          )
          ..activityEvents = [
            ActivityEvent(
              at: DateTime.now().toUtc(),
              title: 'event-$longWord',
              kind: ActivityKind.task,
              outcome: ActivityOutcome.failed,
              workspace: 'name-$longWord',
              detail: 'detail-$longWord ' * 6,
            ),
          ];
        final h = await pumpApp(
          tester,
          llm: awkward(),
          toolkitServer: toolkit,
          size: size,
          onChat: false,
        );
        expect(tester.takeException(), isNull, reason: 'the card');
        h.shell.openToolkitPage(ToolkitPage.library);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'the apps');
        await tapVisible(tester, find.textContaining('Files ·'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'the files');
        h.shell.openToolkitPage(ToolkitPage.activity);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'the activity');
        h.shell.togglePopup(ActivityOpen(toolkit.activityEvents.first.key));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'the event');
      });

      testWidgets('each screen of Add the toolkit fits', (tester) async {
        final h = await pumpApp(tester, size: size, canScan: true);
        h.shell
          ..openSettings()
          ..showGuide(Guide.toolkit);
        await tester.pumpAndSettle();
        for (var n = 0; n < toolkitSteps.length; n++) {
          expect(
            find.text('${n + 1} of ${toolkitSteps.length}'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull, reason: 'screen ${n + 1}');
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
        }
      });
    });
  }

  for (final (size, scale) in cases) {
    final at =
        '${size.width.toInt()}x${size.height.toInt()}'
        '${scale == 1.0 ? '' : ' at ${(scale * 100).toInt()}% text'}';
    group(at, () {
      textScaledTo(scale);

      testWidgets('the workspace\'s pages fit', (tester) async {
        final llm = awkward();
        llm.spaces.first.prompt = 'prompt-$longWord';
        final h = await pumpApp(tester, llm: llm, size: size);
        h.shell.showPane(Pane.files);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        h.shell.openSources();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        h.shell.closeSources();
        for (final page in [FilesSection.instructions, FilesSection.answers]) {
          h.shell.showWorkspacePage(page);
          await h.files.openSection(page);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$page');
        }
        await tester.scrollUntilVisible(
          find.text('Chat model'),
          200,
          scrollable: find
              .descendant(
                of: find.byType(WorkspacePages),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tapVisible(tester, find.text('Chat model').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('each page of the workspace fits', (tester) async {
        final llm = awkward();
        final path = 'custom-documents/file-$longWord.pdf.json';
        final h = await pumpApp(tester, llm: llm, size: size);
        h.shell
          ..showPane(Pane.files)
          ..openSources();
        await tester.pumpAndSettle();
        await h.sources.toggle(h.sources.files.first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await h.files.viewText(path, 'file-$longWord.pdf');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('clear of the phone\'s bars', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.resetPadding);
    final h = await pumpApp(
      tester,
      llm: awkward(),
      size: const Size(360, 640),
      onChat: false,
    );
    h.shell.openSources();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.byType(ChatsTab)).dy,
      greaterThanOrEqualTo(24),
    );
    expect(
      tester.getBottomLeft(find.byType(HomeTabBar)).dy,
      lessThanOrEqualTo(640 - 24),
    );
  });

  testWidgets('turning and resizing the window keeps working', (tester) async {
    final h = await pumpApp(tester, llm: awkward(), size: sizes.first);
    for (final size in [...sizes, ...sizes.reversed]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'at ${size.width}');
    }
    expect(h.chat.activeThread, 't');
  });
}
