import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:everything/adapters/anythingllm_client.dart';
import 'package:everything/core/chat.dart';
import 'package:everything/core/connection.dart';
import 'package:everything/core/ports.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _connection = Connection(
  baseUrl: 'https://host.example.ts.net:3001',
  apiKey: 'SECRET-KEY',
);

HttpAnythingLlmApi _api(
  Future<http.Response> Function(http.Request) handler, {
  Duration timeout = const Duration(seconds: 5),
  Connection? current = _connection,
}) => HttpAnythingLlmApi(
  holder: ConnectionHolder(current),
  client: MockClient(handler),
  timeout: timeout,
);

/// A client that answers [body] to every request and records each one in [seen].
HttpAnythingLlmApi _answering(
  Object body, {
  List<http.Request>? seen,
  int status = 200,
}) => _api((request) async {
  seen?.add(request);
  return http.Response(jsonEncode(body), status);
});

Future<ApiException> _failure(Future<void> call) async {
  try {
    await call;
  } on ApiException catch (error) {
    return error;
  }
  fail('expected an ApiException');
}

void main() {
  group('verify', () {
    test('asks /api/v1/auth with the bearer key', () async {
      late http.Request seen;
      await _api((request) async {
        seen = request;
        return http.Response('{"authenticated":true}', 200);
      }).verify(_connection);
      expect(
        seen.url.toString(),
        'https://host.example.ts.net:3001/api/v1/auth',
      );
      expect(seen.method, 'GET');
      expect(seen.headers['Authorization'], 'Bearer SECRET-KEY');
    });

    test('a 401 says the key was rejected', () async {
      final error = await _failure(
        _api((_) async => http.Response('{"error":"Invalid API Key"}', 401))
            .verify(_connection),
      );
      expect(error.message, 'The server rejected the key.');
      expect(error.status, 401);
    });

    test('a 403 says the key was rejected', () async {
      final error = await _failure(
        _api((_) async => http.Response('', 403)).verify(_connection),
      );
      expect(error.message, 'The server rejected the key.');
    });

    test('another failure gives the server\'s own words', () async {
      final error = await _failure(
        _api((_) async => http.Response('{"error":"database is locked"}', 500))
            .verify(_connection),
      );
      expect(error.message, 'database is locked');
      expect(error.status, 500);
    });

    test('a failure with no words gives the status', () async {
      final error = await _failure(
        _api((_) async => http.Response('<html>', 502)).verify(_connection),
      );
      expect(error.message, 'The server answered HTTP 502.');
    });

    test('an answer that is not JSON is not an AnythingLLM server', () async {
      final error = await _failure(
        _api((_) async => http.Response('<html>login</html>', 200))
            .verify(_connection),
      );
      expect(error.message, contains('did not answer like an AnythingLLM'));
    });

    test('authenticated false is refused', () async {
      final error = await _failure(
        _api((_) async => http.Response('{"authenticated":false}', 200))
            .verify(_connection),
      );
      expect(error.message, 'The server did not accept the key.');
    });

    test('a refused connection names the host', () async {
      final error = await _failure(
        _api((_) async => throw const SocketException('Connection refused'))
            .verify(_connection),
      );
      expect(error.message, contains('host.example.ts.net'));
      expect(error.message, contains('Connection refused'));
    });

    test('a bad certificate says so', () async {
      final error = await _failure(
        _api((_) async => throw const HandshakeException()).verify(_connection),
      );
      expect(error.message, contains('certificate'));
    });

    test('a transport error from the client is reported', () async {
      final error = await _failure(
        _api((_) async => throw http.ClientException('connection closed'))
            .verify(_connection),
      );
      expect(error.message, contains('connection closed'));
    });

    test('no answer in time is a timeout', () async {
      final error = await _failure(
        _api(
          (_) => Completer<http.Response>().future,
          timeout: const Duration(milliseconds: 20),
        ).verify(_connection),
      );
      expect(error.message, contains('did not answer within'));
    });

    test('no error message carries the key', () async {
      final handlers = <Future<http.Response> Function(http.Request)>[
        (_) async => http.Response('{"error":"nope"}', 500),
        (_) async => http.Response('', 401),
        (_) async => throw const SocketException('down'),
        (_) async => throw http.ClientException('closed'),
        (_) async => http.Response('not json', 200),
      ];
      for (final handler in handlers) {
        final error = await _failure(_api(handler).verify(_connection));
        expect(error.message, isNot(contains('SECRET-KEY')));
      }
    });
  });

  group('with no connection in use', () {
    test('every read is NotConfigured, and nothing is sent', () async {
      var sent = 0;
      final api = _api((_) async {
        sent++;
        return http.Response('{}', 200);
      }, current: null);
      await expectLater(api.workspaces(), throwsA(isA<NotConfigured>()));
      await expectLater(api.history('w', 't'), throwsA(isA<NotConfigured>()));
      await expectLater(
        api.streamChat('w', 't', 'hi', mode: ChatMode.query).toList(),
        throwsA(isA<NotConfigured>()),
      );
      await expectLater(
        api.updateEmbeddings('w', adds: ['a']),
        throwsA(isA<NotConfigured>()),
      );
      await expectLater(
        api.upload('a.md', const [1]),
        throwsA(isA<NotConfigured>()),
      );
      expect(sent, 0);
    });

    test('reads the connection when each call is made', () async {
      final seen = <http.Request>[];
      final holder = ConnectionHolder();
      final api = HttpAnythingLlmApi(
        holder: holder,
        client: MockClient((request) async {
          seen.add(request);
          return http.Response('{"workspaces":[]}', 200);
        }),
      );
      holder.current = _connection;
      await api.workspaces();
      expect(seen.single.headers['Authorization'], 'Bearer SECRET-KEY');
    });
  });

  group('an empty answer', () {
    test('is not an AnythingLLM server, except to a delete', () async {
      final api = _api((request) async => http.Response('', 200));
      final error = await _failure(api.workspaces());
      expect(
        error.message,
        'The address did not answer like an AnythingLLM server.',
      );
      await api.deleteThread('s', 't');
    });
  });

  group('workspaces', () {
    test('lists each with its model and named threads', () async {
      final seen = <http.Request>[];
      final list = await _answering({
        'workspaces': [
          {
            'id': 1,
            'name': 'AnythingLLM',
            'slug': 'algorithms',
            'threads': [
              {'user_id': null, 'slug': 't1', 'name': 'Budget'},
              {'slug': 't2', 'name': null},
            ],
          },
          {'slug': 'bare', 'name': null, 'threads': null},
        ],
      }, seen: seen).workspaces();
      expect(
        seen.single.url.toString(),
        'https://host.example.ts.net:3001/api/v1/workspaces',
      );
      expect(list.map((w) => w.name), ['AnythingLLM', 'bare']);
      expect(list.first.threads.map((t) => (t.slug, t.name)), [
        ('t1', 'Budget'),
        ('t2', 'Chat'),
      ]);
      expect(list.last.threads, isEmpty);
    });

    test('one workspace is the first of the list the server sends', () async {
      final seen = <http.Request>[];
      final workspace = await _answering({
        'workspace': [
          {
            'slug': 'my space',
            'name': 'Mine',
            'documents': [
              {
                'docpath': 'claude/a.md-1.json',
                'filename': 'a.md-1.json',
                'metadata': '{"title":"Agents","wordCount":3}',
              },
              {'docpath': 'claude/b.json', 'metadata': 'not json'},
            ],
          },
        ],
      }, seen: seen).workspace('my space');
      expect(seen.single.url.path, '/api/v1/workspace/my%20space');
      expect(workspace.documents.map((d) => d.title), ['Agents', 'b.json']);
      expect(workspace.documents.first.path, 'claude/a.md-1.json');
      expect(workspace.documents.first.words, 3);
      expect(workspace.documents.last.words, isNull);
    });

    test('an empty list is a missing workspace', () async {
      final error = await _failure(
        _answering({'workspace': []}).workspace('gone'),
      );
      expect(error.status, 404);
      expect(error.message, 'There is no workspace gone.');
    });
  });

  group('accepted extensions', () {
    test('are every extension of every type, in lower case', () async {
      final seen = <http.Request>[];
      final extensions = await _answering({
        'types': {
          'text/plain': ['.txt', '.MD'],
          'application/pdf': ['.pdf'],
        },
      }, seen: seen).acceptedExtensions();
      expect(seen.single.url.path, '/api/v1/document/accepted-file-types');
      expect(extensions, {'.txt', '.md', '.pdf'});
    });
  });

  group('upload', () {
    test('posts the file as multipart with the key', () async {
      final seen = <http.Request>[];
      final made = await _answering({
        'success': true,
        'error': null,
        'documents': [
          {
            'location': 'custom-documents/notes.md-1.json',
            'name': 'notes.md-1.json',
            'title': 'notes.md',
          },
        ],
      }, seen: seen).upload('notes.md', utf8.encode('# hi'));
      final request = seen.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/document/upload');
      expect(request.headers['Authorization'], 'Bearer SECRET-KEY');
      expect(
        request.headers['content-type'],
        startsWith('multipart/form-data'),
      );
      expect(request.body, contains('name="file"; filename="notes.md"'));
      expect(request.body, contains('# hi'));
      expect(made.single.path, 'custom-documents/notes.md-1.json');
    });

    test('a refusal gives the server\'s reason', () async {
      final error = await _failure(
        _answering({
          'success': false,
          'error': 'Document processing API is not online.',
        }, status: 500).upload('a.md', const [1]),
      );
      expect(error.message, 'Document processing API is not online.');
    });

    test('success false with status 200 is still a refusal', () async {
      final error = await _failure(
        _answering({'success': false, 'error': null}).upload('a.md', const [1]),
      );
      expect(error.message, 'The server could not read a.md in.');
    });
  });

  group('workspace and chat writes', () {
    test('a new workspace posts its name and reads the answer', () async {
      final seen = <http.Request>[];
      final made = await _answering({
        'workspace': {'slug': 'q3', 'name': 'Q3 planning'},
        'message': 'Workspace created',
      }, seen: seen).createWorkspace('Q3 planning');
      expect(seen.single.method, 'POST');
      expect(seen.single.url.path, '/api/v1/workspace/new');
      expect(jsonDecode(seen.single.body), {'name': 'Q3 planning'});
      expect(
        seen.single.headers['content-type'],
        startsWith('application/json'),
      );
      expect((made.slug, made.name), ('q3', 'Q3 planning'));
    });

    test(
      'a new workspace with no workspace in the answer is a failure',
      () async {
        final error = await _failure(
          _answering({'workspace': null, 'message': 'Name taken'})
              .createWorkspace('x'),
        );
        expect(error.message, 'Name taken');
      },
    );

    test('a new chat is a thread named New chat', () async {
      final seen = <http.Request>[];
      final thread = await _answering({
        'thread': {'slug': 'th-1', 'name': 'New chat'},
      }, seen: seen).createThread('my space');
      expect(seen.single.url.path, '/api/v1/workspace/my%20space/thread/new');
      expect(jsonDecode(seen.single.body), {'name': 'New chat'});
      expect((thread.slug, thread.name), ('th-1', 'New chat'));
    });

    test('renaming posts the name to the thread', () async {
      final seen = <http.Request>[];
      await _answering({
        'thread': {'slug': 't', 'name': 'Budget'},
      }, seen: seen).renameThread('w', 't', 'Budget');
      expect(seen.single.url.path, '/api/v1/workspace/w/thread/t/update');
      expect(jsonDecode(seen.single.body), {'name': 'Budget'});
    });

    test('deleting takes the server\'s empty answer as success', () async {
      final seen = <http.Request>[];
      await _api((request) async {
        seen.add(request);
        return http.Response('', 200);
      }).deleteThread('w', 't');
      expect(seen.single.method, 'DELETE');
      expect(seen.single.url.path, '/api/v1/workspace/w/thread/t');
    });

    test('a history is each turn with its cited titles', () async {
      final seen = <http.Request>[];
      final turns = await _answering({
        'history': [
          {'role': 'user', 'content': 'What is due?', 'sentAt': 1},
          {
            'role': 'assistant',
            'content': 'The roadmap.',
            'sources': [
              {'title': 'roadmap.pdf', 'chunk': '...'},
              {'title': 'roadmap.pdf', 'chunk': '...'},
              {'title': 'notes.md'},
            ],
          },
        ],
      }, seen: seen).history('w', 't');
      expect(seen.single.url.path, '/api/v1/workspace/w/thread/t/chats');
      expect(turns.map((t) => t.text), ['What is due?', 'The roadmap.']);
      expect(turns.last.citations, ['roadmap.pdf', 'notes.md']);
    });

    test('embedding changes post the adds and deletes', () async {
      final seen = <http.Request>[];
      await _answering({
        'workspace': {},
      }, seen: seen).updateEmbeddings('w', adds: ['custom-documents/a.json']);
      expect(seen.single.url.path, '/api/v1/workspace/w/update-embeddings');
      expect(jsonDecode(seen.single.body), {
        'adds': ['custom-documents/a.json'],
        'deletes': <String>[],
      });
    });
  });

  group('stream chat', () {
    /// A client that streams [lines] back, one chunk each, and records the request.
    HttpAnythingLlmApi streaming(
      List<String> lines, {
      List<http.BaseRequest>? seen,
      int status = 200,
    }) => HttpAnythingLlmApi(
      holder: ConnectionHolder(_connection),
      client: MockClient.streaming((request, body) async {
        seen?.add(request);
        await body.drain<void>();
        return http.StreamedResponse(
          Stream.fromIterable([for (final l in lines) utf8.encode(l)]),
          status,
        );
      }),
    );

    String data(Map<String, Object?> chunk) => 'data: ${jsonEncode(chunk)}\n\n';

    test(
      'posts the message and mode, and yields the text then the sources',
      () async {
        final seen = <http.BaseRequest>[];
        final events = await streaming([
          data({
            'type': 'textResponseChunk',
            'textResponse': 'Hel',
            'close': false,
          }),
          data({
            'type': 'textResponseChunk',
            'textResponse': 'lo',
            'close': false,
          }),
          data({
            'type': 'textResponseChunk',
            'textResponse': '',
            'close': true,
            'sources': [
              {'title': 'roadmap.pdf'},
            ],
          }),
        ], seen: seen).streamChat('w', 't', 'Hi', mode: ChatMode.chat).toList();
        expect(
          seen.single.url.path,
          '/api/v1/workspace/w/thread/t/stream-chat',
        );
        expect(seen.single.headers['Authorization'], 'Bearer SECRET-KEY');
        expect(
          [
            for (final e in events)
              e is TextChunk ? e.text : (e as ChatDone).citations,
          ],
          [
            'Hel',
            'lo',
            ['roadmap.pdf'],
          ],
        );
      },
    );

    test('a chunk split across reads is joined before it is parsed', () async {
      final line = data({'textResponse': 'whole', 'close': true});
      final events = await streaming([
        line.substring(0, 12),
        line.substring(12),
      ]).streamChat('w', 't', 'Hi', mode: ChatMode.query).toList();
      expect((events.first as TextChunk).text, 'whole');
      expect(events.last, isA<ChatDone>());
    });

    test('a stream that ends without close still finishes', () async {
      final events = await streaming([
        data({'textResponse': 'part'}),
        ': keep-alive\n\n',
        'data: not json\n\n',
      ]).streamChat('w', 't', 'Hi', mode: ChatMode.query).toList();
      expect(events.length, 2);
      expect(events.last, isA<ChatDone>());
    });

    test('an error chunk fails with the server\'s words', () async {
      final stream = streaming([
        data({
          'type': 'abort',
          'textResponse': null,
          'error': 'No LLM set',
          'close': true,
        }),
      ]).streamChat('w', 't', 'Hi', mode: ChatMode.query);
      await expectLater(
        stream.toList(),
        throwsA(
          isA<ApiException>().having((e) => e.message, 'message', 'No LLM set'),
        ),
      );
    });

    test('a refused request is decoded like any other', () async {
      final stream = streaming([
        '{"error":"Invalid API Key"}',
      ], status: 403).streamChat('w', 't', 'Hi', mode: ChatMode.query);
      await expectLater(
        stream.toList(),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
      );
    });
  });
}
