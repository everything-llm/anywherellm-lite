import 'dart:convert';

import 'package:anywherellm/adapters/anythingllm_client.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _connection = Connection(
  baseUrl: 'https://host.example.ts.net:3001',
  apiKey: 'SECRET-KEY',
  password: 'PASS-WORD',
);

HttpAnythingLlmApi _api(Future<http.Response> Function(http.Request) handler) =>
    HttpAnythingLlmApi(
      holder: ConnectionHolder(_connection),
      client: MockClient(handler),
      timeout: const Duration(seconds: 5),
    );

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

const _memory = {
  'workspace': 'q3',
  'count': 3,
  'facts': [
    {
      'id': 'm12',
      'scope': 'global',
      'text': 'Takes coffee black.',
      'created': '2026-10-11T08:00:00+00:00',
    },
    {'id': 'm9', 'scope': 'workspace', 'text': 'Reports go to Maja.'},
    {'id': 3},
  ],
  'files': [
    {'path': '/project/manual.txt', 'parts': 38, 'ingested': '2026-10-01'},
  ],
  'waiting': [
    {'path': '/work/receipts/a.txt', 'parts': 4},
  ],
  'failed': [
    {'path': '/work/b.txt', 'error': 'not text'},
  ],
};

void main() {
  group('the long-term memory', () {
    test(
      'is read from the host\'s cards port with the key, never the password',
      () async {
        final seen = <http.Request>[];
        final api = _api((request) async {
          seen.add(request);
          return _json(_memory);
        });
        final memory = (await api.longMemory('q3'))!;
        expect(
          seen.single.url.toString(),
          'https://host.example.ts.net:8445/_live/memory/q3',
        );
        expect(seen.single.headers['Authorization'], 'Bearer SECRET-KEY');
        expect(memory.count, 3);
        expect([for (final f in memory.facts) f.id], ['m12', 'm9']);
        expect(memory.facts.first.global, isTrue);
        expect(memory.facts.first.created, isNotNull);
        expect(memory.files.single.parts, 38);
        expect(memory.waiting.single.path, '/work/receipts/a.txt');
        expect(memory.failed.single.error, 'not text');
      },
    );

    test(
      'is null on a host without the route, which is not asked again',
      () async {
        var asked = 0;
        final api = _api((_) async {
          asked++;
          return http.Response('Not Found', 404);
        });
        expect(await api.longMemory('q3'), isNull);
        expect(await api.longMemory('q3'), isNull);
        expect(asked, 1);
      },
    );

    test('recall asks by meaning and reads facts and parts of files', () async {
      final seen = <http.Request>[];
      final api = _api((request) async {
        seen.add(request);
        return _json({
          'hits': [
            {
              'score': 0.81,
              'id': 'm12',
              'scope': 'global',
              'text': 'Takes coffee black.',
              'created': '2026-10-11T08:00:00+00:00',
            },
            {
              'score': 0.62,
              'path': '/project/manual.txt',
              'part': 3,
              'text': 'Descale monthly.',
              'ingested': '2026-10-01',
            },
          ],
        });
      });
      final hits = await api.recallMemory('q3', 'coffee & tea');
      expect(seen.single.url.path, '/_live/memory/q3/recall');
      expect(seen.single.url.queryParameters['q'], 'coffee & tea');
      expect(hits.first.fact!.id, 'm12');
      expect(hits.last.fact, isNull);
      expect((hits.last.path, hits.last.part), ('/project/manual.txt', 3));
    });

    test('remember sends the fact and its scope as JSON', () async {
      final seen = <http.Request>[];
      final api = _api((request) async {
        seen.add(request);
        return _json({
          'fact': {'id': 'm13', 'scope': 'workspace', 'text': 'Likes tea.'},
          'new': false,
        });
      });
      final kept = await api.rememberLong('q3', 'Likes tea.', global: false);
      expect(seen.single.method, 'POST');
      expect(seen.single.url.path, '/_live/memory/q3/remember');
      expect(
        seen.single.headers['Content-Type'],
        startsWith('application/json'),
      );
      expect(jsonDecode(seen.single.body), {
        'text': 'Likes tea.',
        'scope': 'workspace',
      });
      expect((kept.fact.id, kept.isNew), ('m13', false));
    });

    test('forget takes a fact by id or a file by path', () async {
      final seen = <http.Request>[];
      final api = _api((request) async {
        seen.add(request);
        return _json({'forgotten': 'm12'});
      });
      await api.forgetLong('q3', fact: 'm12');
      await api.forgetLong('q3', path: '/project/manual.txt');
      expect(seen.first.url.queryParameters, {'id': 'm12'});
      expect(seen.last.url.queryParameters, {'path': '/project/manual.txt'});
      expect(seen.every((r) => r.method == 'POST'), isTrue);
    });

    test('a refusal fails in the host\'s words', () async {
      final api = _api((_) async => _json({'error': 'no fact m99 here'}, 404));
      await expectLater(
        api.forgetLong('q3', fact: 'm99'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'no fact m99 here',
          ),
        ),
      );
    });
  });
}
