import 'dart:convert';

import 'package:anywherellm/core/files.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _settings = WorkspaceSettings({
  'openAiTemp': 0.7,
  'openAiHistory': 20,
  'topN': 4,
  'similarityThreshold': 0.25,
  'chatProvider': null,
  'chatModel': null,
  'agentProvider': null,
  'agentModel': null,
  'vectorSearchMode': 'default',
  'queryRefusalResponse': null,
  'chatMode': 'automatic',
});

FileNode _tree({
  Map<String, Workspace> details = const {},
  List<LibraryFolder>? library,
}) => buildTree(
  workspaces: const [Workspace(slug: 'q3', name: 'Q3 planning')],
  threadsOf: (_) => const [Thread(slug: 'budget', name: 'Budget')],
  details: details,
  library: library,
);

List<String> _paths(FileNode node) => [
  node.path,
  for (final child in node.children) ..._paths(child),
];

String _edited(String key, Object? value) {
  final json = {..._settings.values, key: value};
  return jsonEncode(json);
}

void main() {
  group('the tree', () {
    test('a workspace not yet read shows only its chats', () {
      final tree = _tree();
      expect(_paths(tree), [
        '/',
        '/workspaces',
        '/workspaces/q3',
        '/workspaces/q3/chats',
        '/workspaces/q3/chats/budget',
        '/library',
        '/settings',
        '/settings/models.json',
        '/.env',
        '/keys',
      ]);
    });

    test('a read workspace adds its prompt, settings and document links', () {
      final tree = _tree(
        details: {
          'q3': const Workspace(
            slug: 'q3',
            name: 'Q3 planning',
            settings: _settings,
            documents: [WorkspaceDoc(path: 'custom/a.json', title: 'A')],
          ),
        },
        library: const [
          LibraryFolder(
            name: 'custom',
            files: [LibraryFile(folder: 'custom', name: 'a.json', title: 'A')],
          ),
        ],
      );
      final q3 = nodeAt(tree, '/workspaces/q3')!;
      expect(
        [for (final c in q3.children) c.name],
        ['PROMPT.md', 'settings.json', 'docs', 'chats'],
      );
      final link = nodeAt(tree, '/workspaces/q3/docs/custom/a.json')!;
      expect(
        (link.kind, link.name, link.ref),
        (NodeKind.docLink, 'A', 'custom/a.json'),
      );
      final doc = nodeAt(tree, '/library/custom/a.json')!;
      expect((doc.kind, doc.ref), (NodeKind.libraryDoc, 'custom/a.json'));
    });

    test('badges mark chats and models read only, secrets locked', () {
      final tree = _tree();
      expect(
        nodeAt(tree, '/workspaces/q3/chats/budget')!.badge,
        NodeBadge.readOnly,
      );
      expect(nodeAt(tree, '/workspaces/q3/chats/budget')!.name, 'Budget.md');
      expect(nodeAt(tree, '/settings/models.json')!.badge, NodeBadge.readOnly);
      expect(nodeAt(tree, '/.env')!.badge, NodeBadge.locked);
      expect(nodeAt(tree, '/keys')!.badge, NodeBadge.locked);
    });

    test('nodeAt finds nothing for a path not in the tree', () {
      expect(nodeAt(_tree(), '/workspaces/q3/PROMPT.md'), isNull);
      expect(nodeAt(_tree(), '/library/x'), isNull);
    });
  });

  test('a chat renders as Markdown with each turn and its sources', () {
    expect(
      chatMarkdown('Budget', const [
        ChatMessage(role: Role.user, text: 'What is the budget?'),
        ChatMessage(
          role: Role.assistant,
          text: 'About 40k.\n',
          citations: ['Q3 roadmap.pdf', 'Notes.md'],
        ),
      ]),
      '# Budget\n'
      '\n**You**\n\nWhat is the budget?\n'
      '\n**Answer**\n\nAbout 40k.\n'
      '\nSources: Q3 roadmap.pdf, Notes.md\n',
    );
  });

  group('settings', () {
    test('round-trip unchanged to no changes', () {
      expect(parseSettings(settingsText(_settings), _settings), isEmpty);
    });

    test('a changed value is the only field written', () {
      expect(parseSettings(_edited('topN', 6), _settings), {'topN': 6});
      expect(parseSettings(_edited('chatModel', 'qwen3:8b'), _settings), {
        'chatModel': 'qwen3:8b',
      });
      expect(parseSettings(_edited('openAiTemp', null), _settings), {
        'openAiTemp': null,
      });
    });

    test('a key left out is left as it is', () {
      expect(parseSettings('{"topN": 5}', _settings), {'topN': 5});
    });

    for (final (text, why) in [
      ('{', 'not valid JSON'),
      ('[1]', 'one JSON object'),
      ('{"name": "x"}', 'name is not a workspace setting'),
      (_edited('topN', 0), 'topN must be a whole number of at least 1'),
      (_edited('topN', 2.5), 'topN must be a whole number'),
      (
        _edited('openAiHistory', -1),
        'openAiHistory must be a whole number of at least 0',
      ),
      (_edited('similarityThreshold', 1.5), 'from 0 to 1'),
      (_edited('openAiTemp', '0.7'), 'openAiTemp must be a number'),
      (_edited('chatModel', 3), 'chatModel must be text or null'),
      (_edited('chatMode', 'query'), 'chatMode cannot be changed here'),
    ]) {
      test('refuses $text', () {
        expect(
          () => parseSettings(text, _settings),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              contains(why),
            ),
          ),
        );
      });
    }

    test('read from a workspace\'s JSON, coercing numbers sent as text', () {
      final read = WorkspaceSettings.fromJson({
        'topN': '6',
        'openAiTemp': 1,
        'chatModel': 7,
      })!;
      expect(read.values['topN'], 6);
      expect(read.values['openAiTemp'], 1);
      expect(read.values['chatModel'], isNull);
      expect(read.values.keys, workspaceSettingSpecs.keys);
    });

    test('a workspace JSON without settings has none', () {
      expect(WorkspaceSettings.fromJson({'slug': 'q3'}), isNull);
    });
  });

  group('models.json', () {
    test('keeps provider, model, engine and vector database names', () {
      final text = modelsText({
        'LLMProvider': 'ollama',
        'OllamaLLMModelPref': 'qwen3:8b',
        'EmbeddingEngine': 'native',
        'VectorDB': 'lancedb',
        'MultiUserMode': false,
      });
      expect(jsonDecode(text), {
        'EmbeddingEngine': 'native',
        'LLMProvider': 'ollama',
        'OllamaLLMModelPref': 'qwen3:8b',
        'VectorDB': 'lancedb',
      });
    });

    test('never shows a secret, whatever its key is called', () {
      const secret = 'sk-live-0123456789';
      final text = modelsText({
        'OpenAiKey': secret,
        'AnthropicApiKeyProvider': secret,
        'GenericOpenAiSecretModelPref': secret,
        'AuthTokenEngine': secret,
        'PasswordProvider': secret,
        'LLMProvider': 'openai',
      });
      expect(text, isNot(contains(secret)));
      expect(jsonDecode(text), {'LLMProvider': 'openai'});
    });
  });

  group('library JSON', () {
    test('reads the folders of the documents tree and their files', () {
      final folders = libraryOf({
        'name': 'documents',
        'type': 'folder',
        'items': [
          {
            'name': 'custom-documents',
            'type': 'folder',
            'items': [
              {
                'name': 'notes.md-1f2e.json',
                'type': 'file',
                'title': 'notes.md',
                'wordCount': 120,
              },
              {'name': 'odd', 'type': 'link'},
            ],
          },
          {'name': 'stray.json', 'type': 'file'},
        ],
      });
      expect(folders.single.name, 'custom-documents');
      final file = folders.single.files.single;
      expect(
        (file.path, file.title),
        ('custom-documents/notes.md-1f2e.json', 'notes.md'),
      );
    });

    test('a document without its text says so, and keeps its details', () {
      final doc = DocBody.fromJson({
        'name': 'notes.md-1f2e.json',
        'title': 'notes.md',
        'docAuthor': 'Unknown',
        'docSource': 'a file uploaded by the user.',
        'wordCount': 120,
      });
      expect(doc.text, isNull);
      expect(doc.details, {
        'docSource': 'a file uploaded by the user.',
        'wordCount': '120',
      });
    });

    test('pinned and watched read from numbers or booleans', () {
      final doc = WorkspaceDoc.fromJson({
        'docpath': 'c/a.json',
        'pinned': 1,
        'watched': false,
      });
      expect((doc.pinned, doc.watched), (true, false));
    });
  });
}
