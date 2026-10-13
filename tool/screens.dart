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

import 'dart:convert';

import 'package:anywherellm/core/apps.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/memory.dart';
import 'package:anywherellm/core/outputs.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/core/files.dart';
import 'package:anywherellm/ui/apps/app_sheets.dart';
import 'package:anywherellm/ui/settings/memory_page.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/share/shared_item.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/fake_api.dart';
import '../test/support/fake_toolkit.dart';
import '../test/support/fake_apps.dart';
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
  toolkit.jobs = [
    ScheduledJob(
      name: 'Morning brief',
      cron: '30 6 * * *',
      workspace: 'Household',
      nextRun: tomorrow.toUtc(),
    ),
    ScheduledJob(
      name: 'Roadmap check',
      cron: '0 8 * * 1',
      workspace: 'Q3 planning',
      nextRun: tomorrow.add(const Duration(days: 3)).toUtc(),
    ),
    ScheduledJob(
      name: 'Price watch: boiler service',
      cron: '0 */6 * * *',
      workspace: 'Household',
      nextRun: tomorrow.add(const Duration(hours: 2)).toUtc(),
      lastRun: DateTime(now.year, now.month, now.day, 16).toUtc(),
      lastStatus: 'failed',
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

const _host = 'anythingllm.example.ts.net';
const _flash = AppRef('household', 'flashcards');

/// The prototype's apps in Household, Flashcards with its folder, log and history.
FakeApps _sampleApps() {
  final apps = FakeApps(present: true);
  final now = DateTime.now();
  DateTime at(int daysAgo, int hour, int minute) =>
      DateTime(now.year, now.month, now.day - daysAgo, hour, minute);
  ServerApp app(
    String name,
    String title,
    String kind,
    String summary,
    DateTime when,
  ) => ServerApp(
    ref: AppRef('household', name),
    title: title,
    kind: kind,
    summary: summary,
    modified: when.toUtc(),
    line: 3,
    page: Uri.parse('https://$_host:8465/household/$name/'),
    card: Uri.parse('https://$_host:8466/cards/household/$name.png'),
  );
  apps.spaces['household'] = [
    app('groceries', 'Groceries', 'list', '4 of 6 left', at(0, 8, 30)),
    app('flashcards', 'Flashcards', 'flashcards', '9 due', at(0, 7, 54)),
    app('boiler-fund', 'Boiler fund', 'tracker', '62%', at(0, 7, 10)),
    app('habits', 'Habits', 'tracker', '0 of 3 met today', at(1, 21, 5)),
    app('focus', 'Pomodoro', 'pomodoro', 'Focus · paused', at(1, 16, 40)),
    app('calendar', 'Calendar', 'calendar', 'Sat 10 Oct', at(3, 9, 0)),
  ];
  String time(DateTime t) => '${t.toUtc().toIso8601String().substring(0, 19)}Z';
  final cards = ['hej', 'tack', 'vatten', 'bröd', 'hus'];
  final state = <String, Object?>{
    'deck': 'Swedish basics',
    'goalPerDay': 12,
    'xp': 260,
    'streak': 6,
    'reviewedToday': 0,
    'cards': [
      for (final card in cards) {'sv': card, 'due': true},
    ],
  };
  final lines = [
    jsonEncode({
      'n': 1,
      't': time(at(1, 20, 0)),
      'by': 'agent',
      'ev': 'made',
      'chat': 'Swedish practice',
      'patch': [
        {'op': 'add', 'path': '', 'value': state},
      ],
    }),
    for (final (i, card) in cards.indexed)
      jsonEncode({
        'n': i + 2,
        't': time(at(0, 7, 50 + i)),
        'by': 'you',
        'ev': 'review',
        'card': card,
        'xp': i < 2 ? 10 : 20,
        'patch': [
          {'op': 'replace', 'path': '/reviewedToday', 'value': i + 1},
          {'op': 'replace', 'path': '/cards/$i/due', 'value': false},
        ],
      }),
  ];
  apps.folders[_flash] = {
    'app.json': const JsonEncoder.withIndent('  ').convert({
      'title': 'Flashcards',
      'kind': 'flashcards',
      'about':
          'A spaced-repetition deck of 14 basic Swedish words. Each answer is one '
          'line in the log; XP, level and streak follow from the log.',
      'rules': [
        'Add cards with patch. Ask before removing a card that has reviews in the log.',
        'Append one line per answer. Never edit or delete past lines.',
        'A missed card comes back 3 cards later. The daily goal is 12 cards.',
      ],
      'schema': {
        'type': 'object',
        'required': ['cards'],
        'properties': {
          'deck': {'type': 'string'},
          'goalPerDay': {'type': 'number'},
          'cards': {'type': 'array'},
        },
      },
      'card': {
        'summary': '{/cards/length} cards',
        'lines': ['Streak: {/streak} days'],
      },
    }),
    'log.jsonl': '${lines.join('\n')}\n',
    'page.html':
        '<!doctype html>\n<title>Flashcards</title>\n<script src="app.js"></script>\n'
        '<main id="card"></main>\n<script>\nApp.start(/*APP*/null);\n'
        'App.onchange(draw);\ndraw();\n</script>\n',
  };
  apps.commits[_flash] = [
    AppCommit(
      commit: '9f46c25e0b1a2c3d4e5f60718293a4b5c6d7e8f9',
      t: at(0, 7, 40).toUtc(),
      by: 'agent',
      chat: 'Swedish practice',
      message:
          'Marks a card missed this session with Again\n\n'
          'A missed card shows Again until it is answered right.',
      subject: 'Marks a card missed this session with Again',
      body: 'A missed card shows Again until it is answered right.',
      files: const ['app.json', 'page.html'],
      revertable: true,
    ),
    AppCommit(
      commit: 'c9ddf09a1b2c3d4e5f60718293a4b5c6d7e8f901',
      t: at(1, 20, 30).toUtc(),
      by: 'agent',
      chat: 'Swedish practice',
      message:
          'Raised the daily goal from 10 to 12 cards\n\n'
          'You asked for a little more practice each day.',
      subject: 'Raised the daily goal from 10 to 12 cards',
      body: 'You asked for a little more practice each day.',
      files: const ['app.json'],
      revertable: true,
    ),
    AppCommit(
      commit: 'bc3a7790a1b2c3d4e5f60718293a4b5c6d7e8f90',
      t: at(1, 20, 0).toUtc(),
      by: 'agent',
      chat: 'Swedish practice',
      message: 'Make Flashcards',
      subject: 'Make Flashcards',
      body: '',
      files: const ['app.json', 'page.html'],
      revertable: false,
    ),
  ];
  apps.diffs['c9ddf09a1b2c3d4e5f60718293a4b5c6d7e8f901'] =
      'commit c9ddf09a1b2c3d4e5f60718293a4b5c6d7e8f901\n'
      'Author: agent <agent@apps>\n\n'
      '    Raised the daily goal from 10 to 12 cards\n\n'
      'diff --git a/app.json b/app.json\n'
      '--- a/app.json\n'
      '+++ b/app.json\n'
      '@@ -7,3 +7,3 @@\n'
      '     "Append one line per answer. Never edit or delete past lines.",\n'
      '-    "A missed card comes back 3 cards later. The daily goal is 10 cards."\n'
      '+    "A missed card comes back 3 cards later. The daily goal is 12 cards."\n'
      '   ],\n';
  return apps;
}

/// Opens Flashcards' data, then [page] of it when given.
Future<void> _appData(WidgetTester tester, Harness h, [AppPage? page]) async {
  h.shell.openApp(_flash, data: true);
  await _settle(tester);
  if (page != null) {
    h.shell.showAppPage(page);
    await _settle(tester);
  }
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
    h.shell.togglePopup(const MemorySheet('g:1'));
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
    h.shell.openUpcoming();
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
  'apps': (tester, h) async {
    h.shell.showTab(HomeTab.apps);
    await _settle(tester);
  },
  'appmenu': (tester, h) async {
    h.shell.showTab(HomeTab.apps);
    await _settle(tester);
    h.shell.togglePopup(const AppMenuSheet(_flash));
    await _settle(tester);
  },
  'apprename': (tester, h) async {
    h.shell.showTab(HomeTab.apps);
    await _settle(tester);
    h.shell.togglePopup(const AppRenameSheet(_flash));
    await _settle(tester);
  },
  'appdel': (tester, h) async {
    h.shell.showTab(HomeTab.apps);
    await _settle(tester);
    h.shell.togglePopup(const AppDeleteSheet(_flash));
    await _settle(tester);
  },
  'appopen': (tester, h) async {
    h.shell.openApp(_flash);
    await _settle(tester);
  },
  'appdata': (tester, h) => _appData(tester, h),
  'appjson': (tester, h) => _appData(tester, h, const AppFileOf('app.json')),
  'appjsonraw': (tester, h) async {
    await _appData(tester, h, const AppFileOf('app.json'));
    await tester.tap(control('Show the raw file'));
    await _settle(tester);
  },
  'apppage': (tester, h) => _appData(tester, h, const AppFileOf('page.html')),
  'applog': (tester, h) => _appData(tester, h, const AppLog()),
  'appstate': (tester, h) async {
    await _appData(tester, h, const AppLog());
    final lines = logLinesOf(h.appsServer.folders[_flash]!['log.jsonl']!);
    h.shell.togglePopup(LineSheet(_flash, lines[2], latest: false));
    await _settle(tester);
  },
  'appgit': (tester, h) => _appData(tester, h, const AppGit()),
  'appcommit': (tester, h) async {
    await _appData(tester, h, const AppGit());
    h.shell.togglePopup(
      CommitSheet(_flash, h.appsServer.commits[_flash]![1], first: false),
    );
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
            appsServer: connected ? _sampleApps() : null,
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
