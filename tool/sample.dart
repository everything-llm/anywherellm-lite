// The design prototype's sample server, which `tool/screens.dart` draws the screens over and
// `tool/audit_app.dart` runs the app over: Household and Q3 planning, their documents and chats.

import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/outputs.dart';
import 'package:anywherellm/core/server_models.dart';

import '../test/support/fake_api.dart';

/// The address the sample connection names.
const sampleServerUrl = 'https://anythingllm.example.ts.net:3001';

/// The connection saved for [sampleServer].
const sampleServerConnection = Connection(
  baseUrl: sampleServerUrl,
  apiKey: 'K1',
);

WorkspaceDoc _doc(
  FakeAnythingLlm llm,
  String name,
  int words, {
  String? web,
  String folder = 'custom-documents',
}) {
  if (!llm.folders.contains(folder)) llm.folders.add(folder);
  final doc = LibraryDoc(
    path: web == null ? '$folder/$name.json' : '$folder/url-$web-0f3a.json',
    title: name,
    words: words,
    web: web != null,
    link: web == null ? null : 'https://$web/',
    fileName: web == null ? name : null,
    published: '10/12/2026, 9:30:00 AM',
  );
  llm.library[doc.path] = doc;
  return embedded(doc);
}

/// The folder of the household's papers, as the prototype's Documents groups them.
const _bills = 'Bills and papers';

/// How the prototype's sample answers ran.
const _metrics = AnswerMetrics(
  model: 'llama3.1:8b',
  tokens: 318,
  seconds: 5.2,
  speed: 61,
);

/// The prototype's server: Household and Q3 planning, their documents and chats.
FakeAnythingLlm sampleServer() {
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
        _doc(llm, 'Home insurance.pdf', 6120, folder: _bills),
        _doc(llm, 'Lease agreement.docx', 3480, folder: _bills),
        _doc(llm, 'Recycling schedule.pdf', 410, folder: _bills),
        _doc(
          llm,
          'Example Heating prices',
          640,
          web: 'example-heating.com',
          folder: _bills,
        ),
        _doc(llm, 'Boiler manual.pdf', 9300, folder: 'Manuals'),
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
  llm.system = const {
    'LLMProvider': 'generic-openai',
    'GenericOpenAiModelPref': 'glm-5.3-flash',
    'EmbeddingEngine': 'native',
    'VectorDB': 'lancedb',
    'WhisperProvider': 'local',
    'TTSProvider': 'native',
  };
  llm.vectors = 1284;
  return llm;
}
