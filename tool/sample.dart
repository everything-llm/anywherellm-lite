// The design prototype's sample server, which `tool/screens.dart` draws the screens over and
// `tool/audit_app.dart` runs the app over: Household and Q3 planning, their documents and chats,
// the saved memories, the scheduled jobs and the Activity.

import 'package:anywherellm/core/activity.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/memory.dart';
import 'package:anywherellm/core/outputs.dart';
import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/core/toolkit.dart';

import '../test/support/fake_api.dart';
import '../test/support/fake_toolkit.dart';

/// The address the sample connection names.
const sampleServerUrl = 'https://anythingllm.example.ts.net:3001';

/// The connection saved for [sampleServer].
const sampleServerConnection = Connection(
  baseUrl: sampleServerUrl,
  apiKey: 'K1',
);

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
/// memories, the scheduled jobs and the Activity.
(FakeAnythingLlm, FakeToolkit) sampleServer() {
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
    ToolkitFeature.activity,
  };
  final at16 = DateTime(now.year, now.month, now.day, 16).toUtc();
  toolkit.jobs = [
    ScheduledJob(
      id: '1',
      name: 'Morning brief',
      prompt: 'Give me today in four lines: the weather, the bins, and anything due.',
      cron: '30 6 * * *',
      nextRun: tomorrow.toUtc(),
      lastRun: tomorrow.subtract(const Duration(days: 1)).toUtc(),
      lastStatus: 'completed',
    ),
    ScheduledJob(
      id: '2',
      name: 'Roadmap check',
      prompt: 'Compare the roadmap with last week and list what slipped.',
      cron: '0 8 * * 1',
      nextRun: tomorrow.add(const Duration(days: 3)).toUtc(),
    ),
    ScheduledJob(
      id: '3',
      name: 'Price watch: boiler service',
      prompt: 'Check the boiler service price and tell me if it changed.',
      tools: 2,
      cron: '0 */6 * * *',
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
