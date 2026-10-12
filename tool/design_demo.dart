// The app over the design canvas's sample data, for comparing in Chrome.
// flutter build web -t tool/design_demo.dart -o build/demo
// ?screen= new | chat | documents | drawer | settings | server | connection |
//          appearance | chatprefs | workspaces | files | upcoming | instructions |
//          answers | signin | running
import 'dart:async';

import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/files.dart';
import 'package:anywherellm/core/outputs.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/app.dart';
import 'package:anywherellm/ui/app_scope.dart';
import 'package:anywherellm/ui/chat/dictation.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/shell.dart';
import 'package:anywherellm/ui/state/memory_controller.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/widgets.dart';

import '../test/support/fake_api.dart';
import '../test/support/fake_settings.dart';
import '../test/support/rig.dart';

class _NoDictation implements Dictation {
  @override
  Future<bool> start({
    required void Function(String words) onWords,
    required void Function(DictationEnd how) onDone,
  }) async => false;

  @override
  Future<void> stop() async {}
}

const _host = 'https://anythingllm.example.ts.net';

FakeAnythingLlm _server() {
  final llm = FakeAnythingLlm();
  llm.system = const {
    'LLMProvider': 'ollama',
    'OllamaLLMModelPref': 'llama3.1:8b',
    'EmbeddingEngine': 'native',
    'VectorDB': 'lancedb',
  };
  llm.spaces = [
    FakeWorkspace(
      'q3',
      'Q3 planning',
      threads: const [
        Thread(slug: 'themes', name: 'Interview themes'),
        Thread(slug: 'hiring', name: 'Hiring plan draft'),
        Thread(slug: 'venues', name: 'Offsite venues'),
        Thread(slug: 'research', name: 'Interview research'),
        Thread(slug: 'kickoff', name: 'Kickoff agenda'),
        Thread(slug: 'budget', name: 'Budget questions'),
        Thread(slug: 'priorities', name: 'Quarter priorities'),
      ],
      docs: [
        libraryDoc(llm, 'Q3 roadmap.pdf', words: 4210),
        libraryDoc(llm, 'Customer interviews.docx', words: 12880),
      ],
    ),
    FakeWorkspace('household', 'Household'),
  ];
  llm.histories['budget'] = const [
    ChatMessage(
      role: Role.user,
      text: 'What is the budget for the customer research work this quarter?',
    ),
    ChatMessage(
      role: Role.assistant,
      text:
          'The roadmap sets aside **about 40k** for customer research in Q3, split across '
          'three pieces of work:\n\n'
          '- Twelve follow-up interviews with the accounts named in the March survey\n'
          '- A usability study of the new onboarding flow\n'
          '- Recruiting and incentives for both',
      citations: [
        Citation(
          'Q3 roadmap.pdf',
          passages: [
            Passage(
              'Customer research: about 40k across the quarter, split between twelve '
              'follow-up interviews, a usability study of onboarding, and recruiting and '
              'incentives for both.',
              score: 0.82,
            ),
            Passage(
              'If the quarter runs over, the usability study is the first item to cut.',
              score: 0.47,
            ),
          ],
        ),
      ],
      metrics: AnswerMetrics(
        model: 'llama3.1:8b',
        tokens: 318,
        seconds: 5.2,
        speed: 61,
      ),
    ),
  ];
  final today = DateTime.now();
  DateTime at(int day, int h, int m) =>
      DateTime(today.year, today.month, today.day + day, h, m).toUtc();
  llm.jobs = [
    ScheduledJob(
      name: 'Morning brief',
      cron: '30 6 * * *',
      workspace: 'Household',
      nextRun: at(1, 6, 30),
      lastRun: at(0, 6, 31),
      lastStatus: 'completed',
    ),
    ScheduledJob(
      name: 'Roadmap check',
      cron: '0 8 * * 1',
      workspace: 'Q3 planning',
      nextRun: at(2, 8, 0),
      lastRun: at(-5, 8, 0),
      lastStatus: 'completed',
    ),
    ScheduledJob(
      name: 'Price watch: boiler service',
      cron: '0 */6 * * *',
      workspace: 'Household',
      nextRun: at(0, 22, 0),
      lastRun: at(0, 16, 0),
      lastStatus: 'failed',
    ),
  ];
  return llm;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final screen = Uri.base.queryParameters['screen'] ?? 'chat';
  final llm = _server();
  final key = Prefs.offKey(_host, 'q3');
  final rig = Rig(
    llm: llm,
    connection: screen == 'signin'
        ? null
        : const Connection(baseUrl: _host, apiKey: 'K1'),
    prefsStore: FakePrefsStore(
      Prefs(
        theme: Uri.base.queryParameters['theme'] == 'dark'
            ? ThemePref.dark
            : ThemePref.light,
        lastChat: LastChat('q3', screen == 'new' ? null : 'budget', _host),
        pinned: {
          key: const ['priorities'],
        },
        recent: {
          key: const ['budget', 'kickoff', 'research'],
        },
        switchedOff: {
          key: const [
            OffDoc(
              path: 'custom-documents/url-pricing-page.json',
              title: 'Pricing page',
              words: 1040,
            ),
          ],
        },
      ),
    ),
  );
  final shell = ShellController(sourcesPinned: false);
  final memory = MemoryController(llm, rig.settings, rig.chat);
  await rig.prefs.load();
  runApp(
    AnywhereLlmApp(
      prefs: rig.prefs,
      home: AppScope(
        shell: shell,
        settings: rig.settings,
        prefs: rig.prefs,
        chat: rig.chat,
        sources: rig.sources,
        files: rig.files,
        system: rig.system,
        memory: memory,
        launch: (url) async => true,
        save: (name, bytes) async => null,
        dictation: _NoDictation(),
        labelAnswers: true,
        child: const AppShell(),
      ),
    ),
  );
  await rig.chat.load();
  await rig.settings.readAuth();
  if (screen == 'new') rig.chat.newChat();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  switch (screen) {
    case 'documents':
      shell.openSources();
    case 'drawer':
      shell.toggleSide();
    case 'workspaces':
      shell.toggleSide();
      shell.togglePopup(Popup.workspaces);
    case 'upcoming':
      shell.openPhonePage(PhonePage.upcoming);
    case 'settings':
      shell.openSettings();
    case 'server':
      shell.openSettings(SettingsPage.server);
    case 'connection':
      shell.openSettings(SettingsPage.connection);
    case 'appearance':
      shell.openSettings(SettingsPage.appearance);
    case 'chatprefs':
      shell.openSettings(SettingsPage.chat);
    case 'files':
      shell.showPane(Pane.files);
    case 'signin':
      shell.openSettings(SettingsPage.connection);
    case 'instructions' || 'answers':
      shell.showPane(Pane.files);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final section = screen == 'instructions'
          ? FilesSection.instructions
          : FilesSection.answers;
      shell.showWorkspacePage(section);
      await rig.files.openSection(section);
    case 'running':
      llm.hold = true;
      rig.chat.newChat();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      unawaited(rig.chat.send('Draft an agenda for the interview kickoff.'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      llm.chat!.add(
        const TextChunk(
          'Here is a 45-minute agenda for the kickoff. Start with the goals and the twelve '
          'accounts named in the March survey, then agree the',
        ),
      );
  }
}
