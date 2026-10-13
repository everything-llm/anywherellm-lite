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

String _edited(String key, Object? value) {
  final json = {..._settings.values, key: value};
  return jsonEncode(json);
}

void main() {
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
      for (final mode in ['chat', 'query']) {
        expect(parseSettings(_edited('chatMode', mode), _settings), {
          'chatMode': mode,
        });
      }
    });

    test('a choice the server left null may stay null', () {
      final unset = WorkspaceSettings({..._settings.values, 'chatMode': null});
      expect(parseSettings(settingsText(unset), unset), isEmpty);
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
      (
        _edited('chatMode', 'agent'),
        'chatMode must be one of automatic, chat, query',
      ),
      (
        _edited('chatMode', null),
        'chatMode must be one of automatic, chat, query',
      ),
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

  group('documents JSON', () {
    test('a document without its text says so', () {
      final doc = DocBody.fromJson({
        'name': 'notes.md-1f2e.json',
        'title': 'notes.md',
        'docAuthor': 'Unknown',
        'docSource': 'a file uploaded by the user.',
        'wordCount': 120,
      });
      expect(doc.text, isNull);
      expect(doc.title, 'notes.md');
    });

    test('pinned reads from a number or a boolean', () {
      final doc = WorkspaceDoc.fromJson({'docpath': 'c/a.json', 'pinned': 1});
      expect(doc.pinned, isTrue);
    });

    test('a web page is one whose chunk source is a link', () {
      bool? web(Map<String, Object?> metadata) => WorkspaceDoc.fromJson({
        'docpath': 'c/a.json',
        'metadata': jsonEncode(metadata),
      }).web;
      expect(web({'chunkSource': 'link://https://news.test/a'}), isTrue);
      expect(web({'chunkSource': ''}), isFalse);
      expect(web({'title': 'a.md'}), isNull);
      expect(WorkspaceDoc.fromJson({'docpath': 'c/a.json'}).web, isNull);
    });
  });

  test('a document keeps each passage read from it, closest first', () {
    final cited = citationsOf([
      {
        'title': 'Q3 roadmap.pdf',
        'text': '<document_metadata>\ntitle: Q3\n</document_metadata>\n\nCut first.',
        'score': 0.47,
      },
      {'title': 'Q3 roadmap.pdf', 'text': 'About 40k.', 'score': 0.82},
      {'title': 'Q3 roadmap.pdf', 'text': 'No score.'},
      {'title': 'Q3 roadmap.pdf', 'text': 'Odd score.', 'score': 7},
      {'title': 'Notes.md'},
    ]);
    expect(cited.map((c) => c.title), ['Q3 roadmap.pdf', 'Notes.md']);
    expect(
      [for (final p in cited.first.passages) (p.text, p.score)],
      [
        ('About 40k.', 0.82),
        ('Cut first.', 0.47),
        ('No score.', null),
        ('Odd score.', null),
      ],
    );
    expect(cited.last.passages, isEmpty);
  });

  test(
    'a web source keeps its page, once per address; a document once per title',
    () {
      final cited = citationsOf([
        {'title': 'A story', 'chunkSource': 'link://https://news.test/a?b=1'},
        {'title': 'A story', 'chunkSource': 'link://https://news.test/a?b=1'},
        {'title': 'A story', 'chunkSource': 'link://https://news.test/other'},
        {'title': 'Q3 roadmap.pdf', 'chunkSource': ''},
        {'title': 'Q3 roadmap.pdf', 'chunkSource': ''},
        {'title': 'Odd', 'chunkSource': 'link://javascript:alert(1)'},
        {'title': 'Uploaded page', 'url': 'file://example.com_.html'},
      ]);
      expect(
        [for (final c in cited) (c.title, c.url?.toString())],
        [
          ('A story', 'https://news.test/a?b=1'),
          ('A story', 'https://news.test/other'),
          ('Q3 roadmap.pdf', null),
          ('Odd', null),
          ('Uploaded page', null),
        ],
      );
    },
  );

  test('a document\'s text is saved under its title, as a text file', () {
    expect(textFileName('Q3 roadmap.pdf'), 'Q3 roadmap.pdf.txt');
    expect(textFileName('notes.md'), 'notes.md');
    expect(textFileName('meeting-notes.TXT'), 'meeting-notes.TXT');
    expect(textFileName('Version 1.16'), 'Version 1.16.txt');
    expect(textFileName('Q&A: what/why?'), 'Q&A- what-why-.txt');
    expect(textFileName('  '), 'document.txt');
  });

  test('the pages are named plainly', () {
    expect(FilesSection.answers.title, 'Answer settings');
  });
}
