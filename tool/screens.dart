// Each screen of the app drawn at a phone's size, 390 by 844 logical pixels at one pixel each,
// in the light and the dark theme, over the test fakes holding the design prototype's sample
// data, to be laid beside the prototype's own pictures:
//
//   flutter test tool/screens.dart
//
// writes `<screen>-light.png` and `<screen>-dark.png` to `$SCREENS` or else `build/screens`.
// `flutter test tool/screens.dart --plain-name chats` draws one screen. It sits outside `test/`,
// so the suite does not run it.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:anywherellm/core/activity.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/library.dart';
import 'package:anywherellm/core/memory.dart';
import 'package:anywherellm/core/outputs.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/core/files.dart';
import 'package:anywherellm/ui/activity.dart' show ActivityOpen;
import 'package:anywherellm/ui/settings/memory_page.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/settings/walkthrough.dart';
import 'package:anywherellm/ui/share/shared_item.dart';
import 'package:anywherellm/ui/task_sheet.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/fake_api.dart';
import '../test/support/fake_toolkit.dart';
import '../test/support/fake_settings.dart';
import '../test/support/pump.dart';

const _server = 'https://anythingllm.example.ts.net:3001';

final _out = Directory(Platform.environment['SCREENS'] ?? 'build/screens');

/// Loads the app's own faces, which a test otherwise draws as boxes.
Future<void> _loadFonts() async {
  const fonts = {
    'Instrument Sans': 'InstrumentSans.ttf',
    'JetBrains Mono': 'JetBrainsMono.ttf',
  };
  for (final MapEntry(key: family, value: file) in fonts.entries) {
    final loader = FontLoader(family)
      ..addFont(
        File('assets/fonts/$file')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)),
      );
    await loader.load();
  }
}

/// Writes what the window shows to [name].
Future<void> _capture(WidgetTester tester, String name) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & view.size);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('${_out.path}/$name')..parent.createSync(recursive: true);
    file.writeAsBytesSync(png!.buffer.asUint8List());
  });
}

WorkspaceDoc _doc(FakeAnythingLlm llm, String name, int words, {String? web}) {
  final doc = WorkspaceDoc(
    path: web == null
        ? 'custom-documents/$name.json'
        : 'custom-documents/url-$web-0f3a.json',
    title: name,
    words: words,
  );
  llm.library[doc.path] = doc;
  return doc;
}

/// How the prototype's sample answers ran.
const _metrics = AnswerMetrics(
  model: 'llama3.1:8b',
  tokens: 318,
  seconds: 5.2,
  speed: 61,
);

/// The prototype's server: Household and Q3 planning, their documents and chats, the saved
/// memories and the scheduled jobs.
(FakeAnythingLlm, FakeToolkit) _sample() {
  final toolkit = FakeToolkit();
  final llm = FakeAnythingLlm()
    ..answer =
        'This is a sample answer. The prototype does not reach a server, so '
        'every question gets this reply.';
  llm.spaces = [
    FakeWorkspace(
      'household',
      'Household',
      threads: [const Thread(slug: 'errands', name: 'Weekend errands')],
      docs: [
        _doc(llm, 'Boiler manual.pdf', 9300),
        _doc(llm, 'Home insurance.pdf', 6120),
        _doc(llm, 'Lease agreement.docx', 3480),
        _doc(llm, 'Example Heating prices', 640, web: 'example-heating.com'),
        _doc(llm, 'Recycling schedule.pdf', 410),
      ],
      prompt:
          'You help run the household. Answer from the documents and say which '
          'one you used.',
    ),
    FakeWorkspace(
      'q3',
      'Q3 planning',
      threads: [
        const Thread(slug: 'budget', name: 'Budget questions'),
        const Thread(slug: 'research', name: 'Interview research'),
      ],
      docs: [
        _doc(llm, 'Q3 roadmap.pdf', 4210),
        _doc(llm, 'Customer interviews.docx', 12880),
      ],
      prompt:
          'You are the planning assistant for the Q3 team. Answer from the '
          'workspace\'s documents and name the file you used.',
    ),
  ];
  llm.histories['errands'] = const [
    ChatMessage(role: Role.user, text: 'When is the boiler service due?'),
    ChatMessage(
      role: Role.assistant,
      text:
          'The boiler manual asks for a service **once a year** by a certified '
          'engineer. Keep the written report, since the warranty asks for it.\n\n'
          'The lease says you book and pay for the yearly service, and the '
          'landlord pays for repairs.',
      citations: [
        Citation('Boiler manual.pdf'),
        Citation('Lease agreement.docx'),
      ],
      metrics: _metrics,
    ),
    ChatMessage(role: Role.user, text: 'Which bins go out this week?'),
    ChatMessage(
      role: Role.assistant,
      text: 'Paper and plastic go out on even weeks, glass and metal on odd weeks.',
      citations: [Citation('Recycling schedule.pdf')],
      metrics: _metrics,
    ),
  ];
  llm.histories['budget'] = const [
    ChatMessage(
      role: Role.user,
      text: 'What is the budget for the customer research work this quarter?',
    ),
    ChatMessage(
      role: Role.assistant,
      text:
          'The roadmap sets aside **about 40k** for customer research in Q3, '
          'split across three pieces of work:\n\n'
          '- Twelve follow-up interviews with the accounts named in the March '
          'survey\n'
          '- A usability study of the new onboarding flow\n'
          '- Recruiting and incentives for both',
      citations: [
        Citation(
          'Q3 roadmap.pdf',
          passages: [
            Passage(
              'Customer research: about 40k across the quarter, split between '
              'twelve follow-up interviews, a usability study of onboarding, '
              'and recruiting and incentives for both.',
              score: 0.82,
            ),
            Passage(
              'If the quarter runs over, the usability study is the first item '
              'to cut.',
              score: 0.47,
            ),
          ],
        ),
      ],
    ),
  ];
  llm.histories['research'] = [
    const ChatMessage(
      role: Role.user,
      text: 'Research how B2B software teams recruit customers for interviews.',
    ),
    ChatMessage(
      role: Role.assistant,
      text:
          'Most teams start with their own customers and look outside only for '
          'the roles they have none of. Four routes come up most often:\n\n'
          '- Account managers or support introduce customers who agreed to be '
          'contacted\n'
          '- A short invitation, by email or in the product, to a screened list\n'
          '- A paid panel for roles the team has no customers in\n'
          '- Past participants asked back for follow-ups',
      citations: [
        for (final (title, site) in const [
          ('How we recruit customers for interviews', 'customer-research'),
          ('Screeners for B2B interviews', 'research-ops'),
          ('Incentives for business participants', 'panel-notes'),
          ('Asking account managers for introductions', 'product-ops'),
          ('Scheduling interviews across time zones', 'research-ops'),
          ('A panel or your own customer list?', 'user-research'),
          ('Consent for recorded interviews', 'interview-notes'),
        ])
          Citation(title, url: Uri.parse('https://$site.example/$title')),
      ],
    ),
  ];
  toolkit.globalMemories.addAll(const [
    SavedMemory(id: 1, text: 'Name is Anna.', global: true),
    SavedMemory(id: 2, text: 'Lives in Uppsala, Sweden.', global: true),
    SavedMemory(
      id: 3,
      text: 'Prefers metric units and 24-hour times.',
      global: true,
    ),
  ]);
  toolkit.workspaceMemories['household'] = [
    const SavedMemory(
      id: 4,
      text: 'The boiler is a Vaillant ecoTEC from 2019.',
      global: false,
    ),
    const SavedMemory(
      id: 5,
      text: 'Bins go out on Tuesday mornings.',
      global: false,
    ),
  ];
  toolkit.workspaceMemories['q3'] = [
    const SavedMemory(
      id: 6,
      text: 'Reports go to Maja on Fridays.',
      global: false,
    ),
  ];
  final now = DateTime.now();
  final tomorrow = DateTime(now.year, now.month, now.day + 1, 6, 30);
  toolkit.served = {
    ToolkitFeature.memories,
    ToolkitFeature.jobs,
    ToolkitFeature.jobsWrite,
    ToolkitFeature.library,
    ToolkitFeature.activity,
  };
  final at16 = DateTime(now.year, now.month, now.day, 16).toUtc();
  toolkit.jobs = [
    ScheduledJob(
      id: '1',
      name: 'Morning brief',
      prompt: 'Give me today in four lines: the weather, the bins, and anything due.',
      cron: '30 6 * * *',
      workspace: 'Household',
      workspaceSlug: 'household',
      nextRun: tomorrow.toUtc(),
      lastRun: tomorrow.subtract(const Duration(days: 1)).toUtc(),
      lastStatus: 'completed',
    ),
    ScheduledJob(
      id: '2',
      name: 'Roadmap check',
      prompt: 'Compare the roadmap with last week and list what slipped.',
      cron: '0 8 * * 1',
      workspace: 'Q3 planning',
      workspaceSlug: 'q3',
      nextRun: tomorrow.add(const Duration(days: 3)).toUtc(),
    ),
    ScheduledJob(
      id: '3',
      name: 'Price watch: boiler service',
      action: 'Check the boiler service price',
      cron: '0 */6 * * *',
      workspace: 'Household',
      workspaceSlug: 'household',
      nextRun: tomorrow.add(const Duration(hours: 2)).toUtc(),
      lastRun: at16,
      lastStatus: 'failed',
    ),
  ];
  toolkit.runRecords['1'] = [
    for (var d = 0; d < 3; d++)
      JobRun(
        startedAt: tomorrow.subtract(Duration(days: d + 1)).toUtc(),
        status: 'completed',
        result: 'Done. The answer is in the chat.',
      ),
  ];
  toolkit.libraryContents = LibraryContents(
    apps: [
      LibraryApp(
        title: 'Groceries',
        page: '/apps-lean/g1.html',
        workspace: 'Household',
        workspaceSlug: 'household',
        change: 'Added Eggs, Oat milk and Coffee',
        changed: at16.subtract(const Duration(days: 1)),
      ),
      LibraryApp(
        title: 'Habits',
        page: '/apps-lean/h1.html',
        workspace: 'Household',
        workspaceSlug: 'household',
        change: 'Marked Evening walk on Monday and Tuesday',
        changed: at16.subtract(const Duration(hours: 10)),
      ),
      LibraryApp(
        title: 'Swedish words',
        page: '/apps-lean/s1.html',
        workspace: 'Household',
        workspaceSlug: 'household',
        change: 'Added 5 cards',
        changed: at16.subtract(const Duration(days: 1)),
      ),
    ],
    files: [
      LibraryFile(
        file: const GeneratedFile(
          type: 'PdfFileDownload',
          name: 'Boiler service quote.pdf',
          storageName: 'quote.pdf',
          size: 86016,
        ),
        workspace: 'Household',
        workspaceSlug: 'household',
        created: at16.subtract(const Duration(days: 1)),
      ),
      LibraryFile(
        file: const GeneratedFile(
          type: 'PdfFileDownload',
          name: 'Household budget.csv',
          storageName: 'budget.csv',
          size: 12288,
        ),
        workspace: 'Household',
        workspaceSlug: 'household',
        created: at16.subtract(const Duration(days: 2)),
      ),
      LibraryFile(
        file: const GeneratedFile(
          type: 'imageGenerationCard',
          name: 'Waste calendar.png',
          storageName: 'waste.png',
          size: 215040,
        ),
        workspace: 'Household',
        workspaceSlug: 'household',
        created: at16.subtract(const Duration(days: 3)),
      ),
      LibraryFile(
        file: const GeneratedFile(
          type: 'PdfFileDownload',
          name: 'Q3 roadmap summary.pdf',
          storageName: 'q3.pdf',
          size: 146432,
        ),
        workspace: 'Q3 planning',
        workspaceSlug: 'q3',
        created: at16,
      ),
    ],
  );
  ActivityEvent event(
    int hoursAgo,
    String title,
    ActivityKind kind, {
    ActivityOutcome outcome = ActivityOutcome.ok,
    String detail = '',
    String workspace = 'Household',
    ActivityLink? link,
  }) => ActivityEvent(
    id: 'e$hoursAgo',
    at: now.toUtc().subtract(Duration(hours: hoursAgo)),
    title: title,
    kind: kind,
    outcome: outcome,
    workspace: workspace,
    detail: detail,
    link: link,
  );
  toolkit.activityEvents = [
    event(
      0,
      'Check the boiler service price',
      ActivityKind.action,
      outcome: ActivityOutcome.failed,
      detail: 'Failed: the site answered 503.',
    ),
    event(
      1,
      'Book a boiler service',
      ActivityKind.action,
      detail: 'Booked Tue 14 Oct · 08:00–10:00, while the agent wrote it.',
    ),
    event(
      2,
      'Morning brief',
      ActivityKind.task,
      detail: 'Done. The answer is in the chat.',
      link: const ChatLink('household', 'errands'),
    ),
    event(
      3,
      'Habits',
      ActivityKind.app,
      detail: 'Marked Evening walk on Monday and Tuesday.',
      link: const PageLink('/apps-lean/h1.html'),
    ),
    event(
      30,
      'Boiler service quote.pdf',
      ActivityKind.file,
      detail: 'The agent made an 84 KB PDF.',
    ),
    event(
      32,
      'Groceries',
      ActivityKind.app,
      detail: 'Added Eggs, Oat milk and Coffee.',
      link: const PageLink('/apps-lean/g1.html'),
    ),
  ];
  llm.system = const {
    'LLMProvider': 'generic-openai',
    'GenericOpenAiModelPref': 'glm-5.3-flash',
    'EmbeddingEngine': 'native',
    'VectorDB': 'lancedb',
    'WhisperProvider': 'local',
    'TTSProvider': 'native',
  };
  llm.vectors = 1284;
  return (llm, toolkit);
}

/// A step that brings a screen up once the app shows its Chats tab.
typedef _Setup = Future<void> Function(WidgetTester tester, Harness h);

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _openChat(WidgetTester tester, Harness h, String thread) async {
  final slug = h.llm.spaces
      .firstWhere((w) => w.threads.any((t) => t.slug == thread))
      .slug;
  h.shell.openChat();
  await h.chat.select(slug, thread: thread);
  await _settle(tester);
}

Future<void> _workspace(WidgetTester tester, Harness h) async {
  h.shell.showPane(Pane.files);
  await _settle(tester);
}

Future<void> _section(
  WidgetTester tester,
  Harness h,
  FilesSection section,
) async {
  await _workspace(tester, h);
  h.shell.showWorkspacePage(section);
  h.files.openSection(section);
  await _settle(tester);
}

Future<void> _settings(
  WidgetTester tester,
  Harness h,
  SettingsPage page,
) async {
  h.shell
    ..openSettings()
    ..showSettingsPage(page);
  await _settle(tester);
}

Thread _thread(Harness h, String slug) =>
    h.llm.spaces.expand((w) => w.threads).firstWhere((t) => t.slug == slug);

final _screens = <String, _Setup>{
  'chats': (tester, h) async {},
  for (var n = 0; n < toolkitSteps.length; n++)
    'toolkit${n + 1}': (tester, h) async {
      h.shell
        ..openSettings()
        ..showGuide(Guide.toolkit);
      await _settle(tester);
      for (var i = 0; i < n; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await _settle(tester);
      }
    },
  'chat': (tester, h) => _openChat(tester, h, 'errands'),
  'hero': (tester, h) async {
    h.chat.newChat();
    h.shell.openChat();
    await _settle(tester);
  },
  'streamed': (tester, h) async {
    h.chat.newChat();
    h.shell.openChat();
    await _settle(tester);
    await h.chat.send('Summarise Boiler manual');
    await _settle(tester);
  },
  'budget': (tester, h) => _openChat(tester, h, 'budget'),
  'research': (tester, h) => _openChat(tester, h, 'research'),
  'settings': (tester, h) async {
    h.shell.openSettings();
    await _settle(tester);
  },
  'conn': (tester, h) => _settings(tester, h, SettingsPage.connection),
  'appear': (tester, h) => _settings(tester, h, SettingsPage.appearance),
  'chatset': (tester, h) => _settings(tester, h, SettingsPage.chat),
  'server': (tester, h) => _settings(tester, h, SettingsPage.server),
  'memory': (tester, h) => _settings(tester, h, SettingsPage.memory),
  'memedit': (tester, h) async {
    await _settings(tester, h, SettingsPage.memory);
    h.shell.togglePopup(const MemorySheet(global: true, id: 1));
    await _settle(tester);
  },
  'memws': (tester, h) async {
    await _settings(tester, h, SettingsPage.memory);
    h.shell.togglePopup(Popup.memoryWorkspace);
    await _settle(tester);
  },
  'chatmodel': (tester, h) => _settings(tester, h, SettingsPage.chatModel),
  'privacy': (tester, h) => _settings(tester, h, SettingsPage.privacy),
  'upcoming': (tester, h) async {
    h.shell.openToolkitPage(ToolkitPage.upcoming);
    await _settle(tester);
  },
  'task': (tester, h) async {
    h.shell.openToolkitPage(ToolkitPage.upcoming);
    await _settle(tester);
    h.shell.togglePopup(const TaskSheet(id: '1'));
    await _settle(tester);
  },
  'newtask': (tester, h) async {
    h.shell.openToolkitPage(ToolkitPage.upcoming);
    await _settle(tester);
    h.shell.togglePopup(const TaskSheet());
    await _settle(tester);
  },
  'library': (tester, h) async {
    h.shell.openToolkitPage(ToolkitPage.library);
    await _settle(tester);
  },
  'libraryfiles': (tester, h) async {
    h.shell.openToolkitPage(ToolkitPage.library);
    await _settle(tester);
    await tester.tap(find.textContaining('Files ·'));
    await _settle(tester);
  },
  'activity': (tester, h) async {
    h.shell.openToolkitPage(ToolkitPage.activity);
    await _settle(tester);
  },
  'run': (tester, h) async {
    h.shell.openToolkitPage(ToolkitPage.activity);
    await _settle(tester);
    h.shell.togglePopup(const ActivityOpen('e0'));
    await _settle(tester);
  },
  'workspace': _workspace,
  'docs': (tester, h) async {
    await _workspace(tester, h);
    h.shell.openSources();
    await _settle(tester);
  },
  'doctext': (tester, h) async {
    await _workspace(tester, h);
    h.shell.openSources();
    await _settle(tester);
    await tester.tap(find.text('Home insurance.pdf'));
    await _settle(tester);
  },
  'instr': (tester, h) => _section(tester, h, FilesSection.instructions),
  'answers': (tester, h) => _section(tester, h, FilesSection.answers),
  'wsmenu': (tester, h) async {
    h.shell.togglePopup(Popup.workspaces);
    await _settle(tester);
  },
  'wsnew': (tester, h) async {
    h.shell.togglePopup(WorkspaceSheet.create);
    await _settle(tester);
  },
  'wsrename': (tester, h) async {
    await _workspace(tester, h);
    h.shell.togglePopup(WorkspaceSheet.rename);
    await _settle(tester);
  },
  'wsdel': (tester, h) async {
    await _workspace(tester, h);
    h.shell.togglePopup(WorkspaceSheet.delete);
    await _settle(tester);
  },
  'chatsheet': (tester, h) async {
    h.shell.openChatSheet(_thread(h, 'errands'));
    await _settle(tester);
  },
  'chatdel': (tester, h) async {
    h.shell.openChatSheet(_thread(h, 'errands'), deleting: true);
    await _settle(tester);
  },
  'attach': (tester, h) async {
    await _openChat(tester, h, 'errands');
    h.shell.togglePopup(Popup.attach);
    await _settle(tester);
  },
  'more': (tester, h) async {
    await _openChat(tester, h, 'errands');
    h.shell.togglePopup(h.chat.turns[1]);
    await _settle(tester);
  },
  'answerfrom': (tester, h) async {
    await _openChat(tester, h, 'errands');
    h.shell.togglePopup(Popup.answerFrom);
    await _settle(tester);
  },
  'passages': (tester, h) async {
    await _openChat(tester, h, 'budget');
    await tester.tap(find.byTooltip('Passages read'));
    await _settle(tester);
  },
  'sources': (tester, h) async {
    await _openChat(tester, h, 'research');
    h.shell.toggleCited(h.chat.turns[1].citations);
    await _settle(tester);
  },
  'shelf': (tester, h) async {
    await _openChat(tester, h, 'errands');
    h.shell.openShelf();
    await _settle(tester);
  },
  'share': (tester, h) async {
    h.shell.showShared(
      SharedLink(
        Uri.parse('https://energy-advice.example/boilers'),
        title: 'Boiler maintenance guide',
      ),
    );
    await _settle(tester);
  },
};

/// The screens drawn with no server saved.
final _signedOut = <String, _Setup>{
  'welcome': (tester, h) async {
    h.shell.openSettings(SettingsPage.connection);
    await _settle(tester);
  },
  'scan': (tester, h) async {
    h.shell
      ..openSettings(SettingsPage.connection)
      ..setScanning(true);
    await _settle(tester);
  },
  for (var n = 0; n < connectSteps.length; n++)
    'howto${n + 1}': (tester, h) async {
      h.shell
        ..openSettings(SettingsPage.connection)
        ..showGuide(Guide.connect);
      await _settle(tester);
      for (var i = 0; i < n; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await _settle(tester);
      }
    },
};

void main() {
  setUpAll(_loadFonts);

  for (final (screens, connected) in [(_screens, true), (_signedOut, false)]) {
    for (final MapEntry(key: name, value: setup) in screens.entries) {
      testWidgets(name, (tester) async {
        for (final theme in [ThemePref.light, ThemePref.dark]) {
          final (llm, toolkit) = _sample();
          final h = await pumpApp(
            tester,
            llm: llm,
            toolkitServer: toolkit,
            canViewApps: true,
            onChat: false,
            canScan: !connected,
            canDictate: true,
            canSpeak: true,
            canPickPhotos: true,
            canShare: true,
            connection: connected
                ? const Connection(baseUrl: _server, apiKey: 'K1')
                : null,
            prefsStore: FakePrefsStore(Prefs(theme: theme)),
          );
          await _settle(tester);
          await setup(tester, h);
          await _capture(tester, '$name-${theme.name}.png');
          // A fresh app for the next theme.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      });
    }
  }
}
