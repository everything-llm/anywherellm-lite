import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anywherellm/adapters/anythingllm_client.dart';
import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/server_models.dart';
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

/// [handler] behind AnythingLLM itself, which has no relay: it answers the relay's health check
/// with its web page, and that request never reaches [handler].
MockClient _notRelay(MockClientStreamHandler handler) =>
    MockClient.streaming((request, body) async {
      if (request.url.path == '/everythingllm/health') {
        return http.StreamedResponse(
          Stream.value(utf8.encode('<!doctype html><html></html>')),
          200,
          headers: {'content-type': 'text/html'},
        );
      }
      return handler(request, body);
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
        api.streamChat('w', 't', 'hi').toList(),
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

  group('without http', () {
    const plain = Connection(baseUrl: 'http://h:3001', apiKey: 'SECRET-KEY');

    test('an http address fails before the key is sent', () async {
      var sent = 0;
      final api = HttpAnythingLlmApi(
        holder: ConnectionHolder(plain),
        allowHttp: false,
        client: MockClient((_) async {
          sent++;
          return http.Response('{"authenticated":true,"workspaces":[]}', 200);
        }),
      );
      final https = isA<ApiException>().having(
        (e) => e.message,
        'message',
        contains('https://'),
      );
      await expectLater(api.verify(plain), throwsA(https));
      await expectLater(api.workspaces(), throwsA(https));
      await expectLater(
        api.streamChat('w', 't', 'hi').toList(),
        throwsA(https),
      );
      expect(sent, 0);
    });

    test('an https address is used', () async {
      final api = HttpAnythingLlmApi(
        holder: ConnectionHolder(_connection),
        allowHttp: false,
        client: MockClient(
          (_) async => http.Response('{"authenticated":true}', 200),
        ),
      );
      await api.verify(_connection);
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
      expect(request.body, isNot(contains('name="metadata"')));
    });

    test('details go as a metadata field of JSON', () async {
      final seen = <http.Request>[];
      await _answering({
        'success': true,
        'error': null,
        'documents': [],
      }, seen: seen).upload(
        'notes.md',
        utf8.encode('# hi'),
        meta: const DocMeta(author: 'Ada', source: ' Finance '),
      );
      expect(seen.single.body, contains('name="metadata"'));
      expect(
        seen.single.body,
        contains('{"docAuthor":"Ada","docSource":"Finance"}'),
      );
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

    test('deleting a workspace sends DELETE and takes a bare OK', () async {
      final seen = <http.Request>[];
      await _api((request) async {
        seen.add(request);
        return http.Response('OK', 200);
      }).deleteWorkspace('scratch');
      expect(seen.single.method, 'DELETE');
      expect(seen.single.url.path, '/api/v1/workspace/scratch');
    });

    test(
      'renaming a workspace posts the name and returns the workspace',
      () async {
        final seen = <http.Request>[];
        final renamed = await _answering({
          'workspace': {'slug': 'scratch', 'name': 'Renamed'},
          'message': null,
        }, seen: seen).renameWorkspace('scratch', 'Renamed');
        expect(seen.single.url.path, '/api/v1/workspace/scratch/update');
        expect(jsonDecode(seen.single.body), {'name': 'Renamed'});
        expect((renamed.slug, renamed.name), ('scratch', 'Renamed'));
      },
    );

    test('a rename the server refuses says why', () async {
      final error = await _failure(
        _answering({'workspace': null, 'message': 'Name taken'})
            .renameWorkspace('scratch', 'Renamed'),
      );
      expect(error.message, 'Name taken');
    });

    test('a delete answered with a web page is not a success', () async {
      final error = await _failure(
        _api((_) async => http.Response('<html>login</html>', 200))
            .deleteWorkspace('scratch'),
      );
      expect(
        error.message,
        'The address did not answer like an AnythingLLM server.',
      );
    });

    test('a history is each turn with its cited titles', () async {
      final seen = <http.Request>[];
      final turns = await _answering({
        'history': [
          {
            'role': 'user',
            'content': 'What is due?',
            'sentAt': 1,
            'attachments': [
              {'name': 'photo.png', 'mime': 'image/png'},
            ],
          },
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
      expect(turns.last.citations.map((c) => c.title), [
        'roadmap.pdf',
        'notes.md',
      ]);
      expect(turns.first.attachments, ['photo.png']);
      expect(turns.last.attachments, isEmpty);
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
      client: _notRelay((request, body) async {
        seen?.add(request);
        await body.drain<void>();
        return http.StreamedResponse(
          Stream.fromIterable([for (final l in lines) utf8.encode(l)]),
          status,
        );
      }),
    );

    String data(Map<String, Object?> chunk) => 'data: ${jsonEncode(chunk)}\n\n';

    test('posts the message, and yields the text then the sources', () async {
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
      ], seen: seen).streamChat('w', 't', 'Hi').toList();
      expect(seen.single.url.path, '/api/v1/workspace/w/thread/t/stream-chat');
      expect(seen.single.headers['Authorization'], 'Bearer SECRET-KEY');
      expect(
        [
          for (final e in events)
            e is TextChunk
                ? e.text
                : [for (final c in (e as ChatDone).citations) c.title],
        ],
        [
          'Hel',
          'lo',
          ['roadmap.pdf'],
        ],
      );
    });

    test('sends no mode, so the workspace\'s own chat mode applies', () async {
      late Map<String, dynamic> body;
      await HttpAnythingLlmApi(
        holder: ConnectionHolder(_connection),
        client: _notRelay((request, bytes) async {
          body = jsonDecode(
            await utf8.decodeStream(bytes),
          ) as Map<String, dynamic>;
          return http.StreamedResponse(
            Stream.value(utf8.encode(data({'close': true}))),
            200,
          );
        }),
      ).streamChat('w', 't', 'Hi').toList();
      expect(body, {'message': 'Hi'});
    });

    test('an empty whole answer keeps the text streamed so far', () async {
      final events = await streaming([
        data({
          'id': 'a',
          'type': 'textResponseChunk',
          'textResponse': 'Looking it up.',
          'sources': [],
          'close': false,
          'error': null,
        }),
        data({
          'id': 'a',
          'type': 'textResponse',
          'textResponse': '',
          'sources': [],
          'close': true,
          'error': null,
        }),
        data({
          'uuid': 'a',
          'type': 'finalizeResponseStream',
          'textResponse': '',
          'sources': [],
          'close': true,
          'error': false,
        }),
      ]).streamChat('w', 't', 'Hi').toList();
      expect(events.whereType<WholeAnswer>(), isEmpty);
      expect(events.whereType<TextChunk>().single.text, 'Looking it up.');
    });

    test('an agent answer: status, then the whole answer, then its sources', () async {
      // As the server streamed one in agent mode, with the text shortened.
      final events = await streaming([
        data({
          'id': 'a',
          'type': 'textResponseChunk',
          'textResponse': '<think>Plan',
          'sources': [],
          'close': false,
          'error': null,
        }),
        data({
          'id': 'a',
          'type': 'textResponseChunk',
          'textResponse': '.</think>',
          'sources': [],
          'close': false,
          'error': null,
        }),
        data({
          'id': 'a',
          'type': 'agentThought',
          'thought':
              '@agent is executing `web-browsing` tool {\n  "query": "news"\n}',
          'sources': [],
          'close': false,
          'error': null,
          'animate': true,
        }),
        data({
          'id': 'a',
          'type': 'agentThought',
          'thought': '@agent: Using SearXNG to search for "news"',
          'sources': [],
          'close': false,
          'error': null,
          'animate': true,
        }),
        data({
          'id': 'a',
          'type': 'textResponseChunk',
          'textResponse': 'Head',
          'sources': [],
          'close': false,
          'error': null,
        }),
        data({
          'id': 'a',
          'type': 'usageMetrics',
          'metrics': {'total_tokens': 9},
          'close': false,
          'error': null,
        }),
        data({
          'id': 'a',
          'type': 'textResponse',
          'textResponse': '<think>Pick.</think>Headline: [x](https://x.test)',
          'sources': [],
          'close': true,
          'error': null,
        }),
        data({
          'uuid': 'a',
          'type': 'finalizeResponseStream',
          'textResponse': '<think>Pick.</think>Headline: [x](https://x.test)',
          'thoughts': [],
          'outputs': [],
          'sources': [
            {
              'title': 'A story',
              'chunkSource': 'link://https://x.test/story',
              'score': 0.5,
            },
            {'title': 'A story'},
            {'title': 'Another'},
          ],
          'close': true,
          'error': false,
        }),
      ]).streamChat('w', 't', 'Hi').toList();
      expect(
        [
          for (final e in events)
            switch (e) {
              TextChunk(:final text) => 'text $text',
              StatusChunk(:final text) => 'status $text',
              WholeAnswer(:final text) => 'whole $text',
              ChatDone(:final citations) =>
                'done ${[for (final c in citations) '${c.title} ${c.url}']}',
            },
        ],
        [
          'text <think>Plan',
          'text .</think>',
          'status Running web-browsing',
          'status Using SearXNG to search for "news"',
          'text Head',
          'whole <think>Pick.</think>Headline: [x](https://x.test)',
          'done [A story https://x.test/story, Another null]',
        ],
      );
    });

    test(
      'a chat answer\'s sources come with its close, before the finalize',
      () async {
        final events = await streaming([
          data({
            'uuid': 'c',
            'type': 'textResponseChunk',
            'textResponse': 'Hi',
            'sources': [],
            'close': false,
            'error': false,
          }),
          data({
            'uuid': 'c',
            'type': 'textResponseChunk',
            'textResponse': '',
            'sources': [
              {'title': 'roadmap.pdf'},
            ],
            'close': true,
            'error': false,
          }),
          data({
            'uuid': 'c',
            'type': 'finalizeResponseStream',
            'close': true,
            'error': false,
            'chatId': 7,
            'sources': [],
          }),
        ]).streamChat('w', 't', 'Hi').toList();
        expect((events.first as TextChunk).text, 'Hi');
        expect(events.whereType<WholeAnswer>(), isEmpty);
        expect(
          (events.last as ChatDone).citations.map((c) => (c.title, c.url)),
          [('roadmap.pdf', null)],
        );
        expect(events.length, 2);
      },
    );

    test('a chunk split across reads is joined before it is parsed', () async {
      final line = data({'textResponse': 'whole', 'close': true});
      final events = await streaming([
        line.substring(0, 12),
        line.substring(12),
      ]).streamChat('w', 't', 'Hi').toList();
      expect((events.first as TextChunk).text, 'whole');
      expect(events.last, isA<ChatDone>());
    });

    test('a stream that ends without close still finishes', () async {
      final events = await streaming([
        data({'textResponse': 'part'}),
        ': keep-alive\n\n',
        'data: not json\n\n',
      ]).streamChat('w', 't', 'Hi').toList();
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
      ]).streamChat('w', 't', 'Hi');
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
      ], status: 403).streamChat('w', 't', 'Hi');
      await expectLater(
        stream.toList(),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
      );
    });

    test('reset posts only the reset flag and reads the reply', () async {
      Object? sent;
      final api = HttpAnythingLlmApi(
        holder: ConnectionHolder(_connection),
        client: MockClient.streaming((request, body) async {
          expect(request.url.path, '/api/v1/workspace/w/thread/t/stream-chat');
          sent = jsonDecode(utf8.decode(await body.expand((b) => b).toList()));
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                data({
                  'textResponse': 'Chat history was reset!',
                  'close': true,
                }),
              ),
            ),
            200,
          );
        }),
      );
      await api.resetChat('w', 't');
      expect(sent, {'reset': true});
    });

    test('a reset the server fails says why', () async {
      final error = await _failure(
        streaming([
          data({'type': 'abort', 'error': 'Thread t not found.'}),
        ]).resetChat('w', 't'),
      );
      expect(error.message, 'Thread t not found.');
    });
  });

  group('slash commands', () {
    test('reads the presets from the system route, with the key', () async {
      final seen = <http.Request>[];
      final presets = await _answering({
        'presets': [
          {
            'id': 1,
            'command': '/deep-research',
            'prompt': '@agent Research:',
            'description': 'Research in depth',
          },
          {'id': 2, 'command': 'broken'},
        ],
      }, seen: seen).slashCommands();
      expect(seen.single.url.path, '/api/system/slash-command-presets');
      expect(seen.single.headers['Authorization'], 'Bearer SECRET-KEY');
      expect([for (final p in presets) p.command], ['/deep-research']);
      expect(presets.single.description, 'Research in depth');
    });

    test('a server with a password refuses them', () async {
      final error = await _failure(
        _answering({
          'error': 'No auth token found.',
        }, status: 401).slashCommands(),
      );
      expect(error.status, 401);
    });
  });

  group('files', () {
    test(
      'a workspace read on its own carries its prompt, settings and pins',
      () async {
        final w = await _answering({
          'workspace': [
            {
              'slug': 'w',
              'name': 'W',
              'openAiPrompt': 'Be brief.',
              'openAiTemp': 0.7,
              'topN': 4,
              'chatMode': 'automatic',
              'documents': [
                {'docpath': 'c/a.json', 'pinned': true, 'watched': false},
              ],
            },
          ],
        }).workspace('w');
        expect(w.prompt, 'Be brief.');
        expect(w.settings!.values['topN'], 4);
        expect(w.documents.single.pinned, isTrue);
      },
    );

    test(
      'a workspace update posts the fields and needs the workspace back',
      () async {
        final seen = <http.Request>[];
        await _answering({
          'workspace': {'slug': 'w'},
          'message': null,
        }, seen: seen).updateWorkspace('w', {'topN': 6, 'openAiPrompt': null});
        expect(seen.single.method, 'POST');
        expect(seen.single.url.path, '/api/v1/workspace/w/update');
        expect(jsonDecode(seen.single.body), {'topN': 6, 'openAiPrompt': null});

        final error = await _failure(
          _answering({'workspace': null, 'message': 'Invalid topN'})
              .updateWorkspace('w', {'topN': 0}),
        );
        expect(error.message, 'Invalid topN');
      },
    );

    test('pinning posts the path and the state', () async {
      final seen = <http.Request>[];
      await _answering({
        'message': 'ok',
      }, seen: seen).pinDocument('w', 'c/a.json', pinned: true);
      expect(seen.single.url.path, '/api/v1/workspace/w/update-pin');
      expect(jsonDecode(seen.single.body), {
        'docPath': 'c/a.json',
        'pinStatus': true,
      });
    });

    test('the library is the folders under the documents root', () async {
      final seen = <http.Request>[];
      final folders = await _answering({
        'localFiles': {
          'name': 'documents',
          'type': 'folder',
          'items': [
            {
              'name': 'claude',
              'type': 'folder',
              'items': [
                {'name': 'a.json', 'type': 'file', 'title': 'a.md'},
              ],
            },
          ],
        },
      }, seen: seen).libraryFolders();
      expect(seen.single.url.path, '/api/v1/documents');
      expect(folders.single.files.single.path, 'claude/a.json');
    });

    test('a document is asked for by its file name alone', () async {
      final seen = <http.Request>[];
      final doc = await _answering({
        'document': {
          'name': 'a.json',
          'title': 'a.md',
          'pageContent': 'Hello.',
        },
      }, seen: seen).document('claude/a.json');
      expect(seen.single.url.path, '/api/v1/document/a.json');
      expect((doc.title, doc.text), ('a.md', 'Hello.'));

      final missing = await _failure(
        _answering({'document': null}).document('claude/b.json'),
      );
      expect(missing.status, 404);
    });

    test('folder, move and delete send what the server expects', () async {
      final seen = <http.Request>[];
      final api = _answering({'success': true, 'message': null}, seen: seen);
      await api.createFolder('notes');
      await api.moveDocuments([('claude/a.json', 'notes/a.json')]);
      await api.removeDocuments(['notes/a.json']);
      await api.removeFolder('notes');
      expect(
        [for (final r in seen) '${r.method} ${r.url.path}'],
        [
          'POST /api/v1/document/create-folder',
          'POST /api/v1/document/move-files',
          'DELETE /api/v1/system/remove-documents',
          'DELETE /api/v1/document/remove-folder',
        ],
      );
      expect(
        [for (final r in seen) jsonDecode(r.body)],
        [
          {'name': 'notes'},
          {
            'files': [
              {'from': 'claude/a.json', 'to': 'notes/a.json'},
            ],
          },
          {
            'names': ['notes/a.json'],
          },
          {'name': 'notes'},
        ],
      );
    });

    test('success false with status 200 is a refusal', () async {
      final api = _answering({'success': false, 'message': 'Folder exists'});
      expect((await _failure(api.createFolder('x'))).message, 'Folder exists');
      expect((await _failure(api.removeFolder('x'))).message, 'Folder exists');
      final quiet = _answering({'success': false});
      expect(
        (await _failure(quiet.removeDocuments(['x']))).message,
        'The server did not delete the documents.',
      );
    });

    test('an upload into a folder goes to that folder\'s route', () async {
      final seen = <http.Request>[];
      await _answering({
        'success': true,
        'documents': <Object>[],
      }, seen: seen).upload('a.md', const [1], folder: 'my notes');
      expect(seen.single.url.path, '/api/v1/document/upload/my%20notes');
    });

    test('the system settings are the settings object', () async {
      final seen = <http.Request>[];
      final settings = await _answering({
        'settings': {'LLMProvider': 'ollama'},
      }, seen: seen).systemSettings();
      expect(seen.single.url.path, '/api/v1/system');
      expect(settings, {'LLMProvider': 'ollama'});
    });

    test('no files error carries the key', () async {
      final api = _api((_) async => http.Response('{"error":"nope"}', 500));
      for (final call in <Future<void> Function()>[
        () => api.updateWorkspace('w', {'topN': 1}),
        () => api.pinDocument('w', 'a', pinned: true),
        api.libraryFolders,
        () => api.document('a'),
        () => api.createFolder('a'),
        () => api.moveDocuments([('a', 'b')]),
        () => api.removeDocuments(['a']),
        api.systemSettings,
      ]) {
        expect((await _failure(call())).message, isNot(contains('SECRET-KEY')));
      }
    });
  });

  group('attachments', () {
    test('go as base64 data URLs with the server\'s types', () async {
      final seen = <http.BaseRequest>[];
      final api = HttpAnythingLlmApi(
        holder: ConnectionHolder(_connection),
        client: _notRelay((request, body) async {
          seen.add(request);
          await body.drain<void>();
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                'data: ${jsonEncode({'type': 'textResponseChunk', 'textResponse': '', 'close': true})}\n\n',
              ),
            ),
            200,
          );
        }),
      );
      await api
          .streamChat(
            'w',
            't',
            'What is this?',
            attachments: [
              Attachment.of('photo.PNG', const [1, 2, 3]),
              Attachment.of('report.pdf', utf8.encode('%PDF')),
            ],
          )
          .toList();
      final body = jsonDecode(
        (seen.single as http.Request).body,
      ) as Map<String, dynamic>;
      expect(body['message'], 'What is this?');
      expect(body['attachments'], [
        {
          'name': 'photo.PNG',
          'mime': 'image/png',
          'contentString': 'data:image/png;base64,AQID',
        },
        {
          'name': 'report.pdf',
          'mime': documentMime,
          'contentString':
              'data:application/pdf;base64,${base64Encode(utf8.encode('%PDF'))}',
        },
      ]);
    });

    test('a document of unknown type is sent as octet-stream', () {
      expect(
        attachmentJson(Attachment.of('notes.xyz', const [0]))['contentString'],
        startsWith('data:application/octet-stream;base64,'),
      );
    });

    test('no attachments leaves the field out', () async {
      final seen = <http.BaseRequest>[];
      final api = HttpAnythingLlmApi(
        holder: ConnectionHolder(_connection),
        client: _notRelay((request, body) async {
          seen.add(request);
          await body.drain<void>();
          return http.StreamedResponse(const Stream.empty(), 200);
        }),
      );
      await api.streamChat('w', 't', 'Hi').toList();
      final body = jsonDecode(
        (seen.single as http.Request).body,
      ) as Map<String, dynamic>;
      expect(body.containsKey('attachments'), isFalse);
    });
  });

  group('links and text', () {
    final made = {
      'success': true,
      'error': null,
      'documents': [
        {
          'location': 'custom-documents/url-example_com-1.json',
          'title': 'example_com.html',
        },
      ],
    };

    test('a link posts the address and returns what was made', () async {
      final seen = <http.Request>[];
      final docs = await _answering(
        made,
        seen: seen,
      ).uploadLink('https://example.com');
      expect(seen.single.url.path, '/api/v1/document/upload-link');
      expect(seen.single.headers['Authorization'], 'Bearer SECRET-KEY');
      expect(jsonDecode(seen.single.body), {'link': 'https://example.com'});
      expect(docs.single.path, 'custom-documents/url-example_com-1.json');
    });

    test('a link sends its details', () async {
      final seen = <http.Request>[];
      await _answering(made, seen: seen).uploadLink(
        'https://example.com',
        meta: const DocMeta(
          title: ' Q3 report ',
          author: 'Ada',
          description: 'Numbers',
          source: 'Finance',
        ),
      );
      expect(jsonDecode(seen.single.body), {
        'link': 'https://example.com',
        'metadata': {
          'title': 'Q3 report',
          'docAuthor': 'Ada',
          'description': 'Numbers',
          'docSource': 'Finance',
        },
      });
    });

    test('text keeps its own title over the details', () async {
      final seen = <http.Request>[];
      await _answering(made, seen: seen).uploadText(
        'Notes',
        'Some text',
        meta: const DocMeta(
          title: ' Q3 report ',
          author: 'Ada',
          description: 'Numbers',
          source: 'Finance',
        ),
      );
      expect(jsonDecode(seen.single.body)['metadata'], {
        'title': 'Notes',
        'docAuthor': 'Ada',
        'description': 'Numbers',
        'docSource': 'Finance',
      });
    });

    test('text posts the text with its title', () async {
      final seen = <http.Request>[];
      await _answering(made, seen: seen).uploadText('Notes', 'Some text');
      expect(seen.single.url.path, '/api/v1/document/raw-text');
      expect(jsonDecode(seen.single.body), {
        'textContent': 'Some text',
        'metadata': {'title': 'Notes'},
      });
    });

    test('success false is a refusal that keeps the key out', () async {
      final link = await _failure(
        _answering({'success': false, 'error': null})
            .uploadLink('https://example.com'),
      );
      expect(link.message, 'The server could not read https://example.com.');
      final text = await _failure(
        _answering({'success': false, 'error': 'Invalid request'})
            .uploadText('Notes', 'x'),
      );
      expect(text.message, 'Invalid request');
      expect('$link $text', isNot(contains('SECRET-KEY')));
    });
  });

  group('search and export', () {
    test('a hit drops the metadata block the server puts first', () async {
      final hits = await _answering({
        'results': [
          {
            'text': '<document_metadata>\nsourceDocument: notes.md\npublished: 10/3/2026\n</document_metadata>\n\nThe passage itself.',
            'metadata': {'title': 'notes.md'},
            'score': 0.3,
          },
          {
            'text': 'No header. <document_metadata>kept</document_metadata>',
            'metadata': {'title': 'b.md'},
            'score': 0.2,
          },
        ],
      }).searchDocs('q3', 'notes');
      expect(
        [for (final h in hits) h.text],
        [
          'The passage itself.',
          'No header. <document_metadata>kept</document_metadata>',
        ],
      );
    });

    test('a search posts the question and reads each hit', () async {
      final seen = <http.Request>[];
      final hits = await _answering({
        'results': [
          {
            'id': '1',
            'text': 'A passage.',
            'metadata': {'title': 'Q3 roadmap.pdf', 'author': 'Unknown'},
            'distance': 0.35,
            'score': 0.65,
          },
          {'id': '2', 'metadata': {}, 'score': 0.4},
        ],
      }, seen: seen).searchDocs('q3', 'budget');
      expect(seen.single.url.path, '/api/v1/workspace/q3/vector-search');
      expect(jsonDecode(seen.single.body), {'query': 'budget'});
      expect(
        [for (final h in hits) (h.title, h.text, h.score)],
        [('Q3 roadmap.pdf', 'A passage.', 0.65), ('Untitled', '', 0.4)],
      );
    });

    test('a search the server refuses says why', () async {
      final error = await _failure(
        _api(
          (_) async => http.Response(
            '{"message":"Query parameter cannot be empty."}',
            400,
          ),
        ).searchDocs('q3', ''),
      );
      expect(error.message, contains('Query parameter cannot be empty.'));
    });

    test('an export is the file as the server sends it', () async {
      final seen = <http.Request>[];
      final bytes = await _api((request) async {
        seen.add(request);
        return http.Response(
          'id,prompt\n1,hi\n',
          200,
          headers: {'content-type': 'text/csv; charset=utf-8'},
        );
      }).exportChats(ChatExport.csv);
      expect(seen.single.url.path, '/api/v1/system/export-chats');
      expect(seen.single.url.queryParameters, {'type': 'csv'});
      expect(seen.single.headers['Authorization'], 'Bearer SECRET-KEY');
      expect(utf8.decode(bytes), 'id,prompt\n1,hi\n');
    });

    test('an export answered with a web page or a bad key fails', () async {
      final page = await _failure(
        _api(
          (_) async => http.Response(
            '<html>login</html>',
            200,
            headers: {'content-type': 'text/html'},
          ),
        ).exportChats(ChatExport.json),
      );
      expect(page.message, isNot(contains('SECRET-KEY')));
      final key = await _failure(
        _api((_) async => http.Response('', 403)).exportChats(ChatExport.json),
      );
      expect(key.message, 'The server rejected the key.');
    });

    test('each format names its file', () {
      expect(
        [for (final f in ChatExport.values) f.fileName],
        [
          'anythingllm-chats.jsonl',
          'anythingllm-chats.json',
          'anythingllm-chats.csv',
          'anythingllm-chats-alpaca.json',
        ],
      );
    });
  });

  group('on a relay', () {
    String event(int id, String name, Object data) =>
        'id: $id\nevent: $name\ndata: ${jsonEncode(data)}\n\n';

    String chunk(int id, Map<String, Object?> data) => event(id, 'chunk', data);

    /// A relay that starts run `r_1` and answers its events with what [follow] gives for each
    /// try, counting from 0. Every request goes into [seen]. The start waits for [started], the
    /// health check answers [probeStatus] for each ask with [health], and a try at the events
    /// answers [eventsStatus].
    HttpAnythingLlmApi relay(
      Stream<List<int>> Function(int attempt) follow, {
      List<http.Request>? seen,
      int startStatus = 201,
      Object? start,
      Future<void>? started,
      int Function(int probe)? probeStatus,
      Object? health,
      int Function(int attempt)? eventsStatus,
      List<Duration> rejoinDelays = const [Duration.zero],
      Duration quiet = const Duration(seconds: 5),
    }) {
      var attempt = 0;
      var probe = 0;
      return HttpAnythingLlmApi(
        holder: ConnectionHolder(_connection),
        quiet: quiet,
        rejoinDelays: rejoinDelays,
        client: MockClient.streaming((request, body) async {
          final bytes = await body.toBytes();
          seen?.add(
            http.Request(request.method, request.url)
              ..headers.addAll(request.headers)
              ..bodyBytes = bytes,
          );
          final path = request.url.path;
          if (path == '/everythingllm/health') {
            final status = probeStatus?.call(probe++) ?? 200;
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  status == 200
                      ? jsonEncode(
                          health ??
                              {
                                'ok': true,
                                'service': 'everythingllm',
                                'features': ['runs'],
                              },
                        )
                      : 'Bad Gateway',
                ),
              ),
              status,
            );
          }
          if (path == '/everythingllm/v1/runs') {
            await started;
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  jsonEncode(start ?? {'id': 'r_1', 'status': 'running'}),
                ),
              ),
              startStatus,
            );
          }
          if (path == '/everythingllm/v1/runs/r_1/events') {
            final n = attempt++;
            final status = eventsStatus?.call(n) ?? 200;
            if (status != 200) {
              return http.StreamedResponse(
                Stream.value(utf8.encode('{"error":"Store busy."}')),
                status,
              );
            }
            return http.StreamedResponse(follow(n), 200);
          }
          if (path == '/everythingllm/v1/runs/r_1/cancel') {
            return http.StreamedResponse(
              Stream.value(utf8.encode('{"id":"r_1","status":"cancelled"}')),
              200,
            );
          }
          return http.StreamedResponse(
            Stream.value(utf8.encode('Not Found')),
            404,
          );
        }),
      );
    }

    Stream<List<int>> lines(List<String> events) =>
        Stream.fromIterable([for (final e in events) utf8.encode(e)]);

    /// [events], then the connection breaking.
    Stream<List<int>> broken(List<String> events) async* {
      yield* lines(events);
      throw http.ClientException('Connection reset');
    }

    test('starts a run of the stream-chat body and reads its chunks', () async {
      final seen = <http.Request>[];
      final events = await relay(
        (_) => lines([
          chunk(1, {
            'type': 'agentThought',
            'thought': '@agent: Using SearXNG to search for news',
          }),
          ': ping\n\n',
          chunk(2, {'type': 'textResponseChunk', 'textResponse': 'Hel'}),
          chunk(3, {
            'type': 'textResponse',
            'textResponse': 'Hello',
            'close': true,
          }),
          chunk(4, {
            'type': 'finalizeResponseStream',
            'sources': [
              {'title': 'News', 'chunkSource': 'link://https://news.example/a'},
            ],
          }),
          event(5, 'done', {}),
        ]),
        seen: seen,
      ).streamChat('w', 't', 'Hi').toList();

      expect(seen.map((r) => '${r.method} ${r.url.path}'), [
        'GET /everythingllm/health',
        'POST /everythingllm/v1/runs',
        'GET /everythingllm/v1/runs/r_1/events',
      ]);
      expect(seen.first.headers.containsKey('Authorization'), isFalse);
      final start = jsonDecode(seen[1].body) as Map<String, dynamic>;
      expect(start['workspace'], 'w');
      expect(start['thread'], 't');
      expect(start['clientId'], matches(RegExp(r'^c_[0-9a-f]{32}$')));
      expect(start['body'], {'message': 'Hi'});
      expect(seen[2].headers['Authorization'], 'Bearer SECRET-KEY');
      expect(seen[2].headers.containsKey('Last-Event-ID'), isFalse);

      expect(events, hasLength(4));
      expect((events[0] as StatusChunk).text, isNotEmpty);
      expect((events[1] as TextChunk).text, 'Hel');
      expect((events[2] as WholeAnswer).text, 'Hello');
      final done = events[3] as ChatDone;
      expect(done.citations.single.url, Uri.parse('https://news.example/a'));
    });

    test('a chat answer ends at done after its closing chunk', () async {
      final events = await relay(
        (_) => lines([
          chunk(1, {'type': 'textResponseChunk', 'textResponse': 'Hi'}),
          chunk(2, {
            'type': 'textResponseChunk',
            'textResponse': '',
            'close': true,
            'sources': [
              {'title': 'notes.md'},
            ],
          }),
          event(3, 'done', {}),
        ]),
      ).streamChat('w', 't', 'Hi').toList();
      expect((events.first as TextChunk).text, 'Hi');
      expect((events.last as ChatDone).citations.single.title, 'notes.md');
    });

    test('attachments go in the run\'s body', () async {
      final seen = <http.Request>[];
      await relay((_) => lines([event(1, 'done', {})]), seen: seen)
          .streamChat(
            'w',
            't',
            'Look',
            attachments: [
              Attachment.of('photo.png', const [1, 2, 3]),
            ],
          )
          .toList();
      final start = jsonDecode(seen[1].body) as Map<String, dynamic>;
      expect((start['body'] as Map)['attachments'], [
        {
          'name': 'photo.png',
          'mime': 'image/png',
          'contentString': 'data:image/png;base64,AQID',
        },
      ]);
    });

    test('asks whether the server is a relay once per connection', () async {
      final seen = <http.Request>[];
      final api = relay((_) => lines([event(1, 'done', {})]), seen: seen);
      await api.streamChat('w', 't', 'One').toList();
      await api.streamChat('w', 't', 'Two').toList();
      expect(
        seen.where((r) => r.url.path == '/everythingllm/health'),
        hasLength(1),
      );
    });

    test('a relay failing when asked is asked again next time', () async {
      final seen = <http.Request>[];
      final api = relay(
        (_) => lines([event(1, 'done', {})]),
        seen: seen,
        probeStatus: (probe) => probe == 0 ? 503 : 200,
      );
      api.streamChat('w', 't', 'One').listen((_) {}, onError: (_) {});
      await pumpEventQueue();
      await api.streamChat('w', 't', 'Two').toList();
      expect(
        seen.where((r) => r.url.path == '/everythingllm/health'),
        hasLength(2),
      );
      expect(
        seen.where((r) => r.url.path == '/everythingllm/v1/runs'),
        hasLength(1),
      );
    });

    test(
      'a web page at the relay\'s health check is AnythingLLM itself',
      () async {
        final paths = <String>[];
        final api = HttpAnythingLlmApi(
          holder: ConnectionHolder(_connection),
          client: MockClient.streaming((request, body) async {
            await body.drain<void>();
            paths.add(request.url.path);
            if (request.url.path == '/everythingllm/health') {
              return http.StreamedResponse(
                Stream.value(utf8.encode('<!doctype html><html></html>')),
                200,
                headers: {'content-type': 'text/html'},
              );
            }
            return http.StreamedResponse(
              Stream.value(utf8.encode('data: {"close":true}\n\n')),
              200,
            );
          }),
        );
        await api.streamChat('w', 't', 'Hi').toList();
        await api.streamChat('w', 't', 'Again').toList();
        expect(paths, [
          '/everythingllm/health',
          '/api/v1/workspace/w/thread/t/stream-chat',
          '/api/v1/workspace/w/thread/t/stream-chat',
        ]);
      },
    );

    for (final (what, health) in [
      (
        'another service',
        {
          'ok': true,
          'service': 'other',
          'features': ['runs'],
        },
      ),
      ('no runs', {'ok': true, 'service': 'everythingllm', 'features': []}),
    ]) {
      test('a health answer naming $what is no relay', () async {
        final seen = <http.Request>[];
        final api = relay(
          (_) => lines([event(1, 'done', {})]),
          seen: seen,
          health: health,
        );
        // The fake has no stream-chat, so the direct answer fails.
        await _failure(api.streamChat('w', 't', 'Hi').drain<void>());
        expect(seen.map((r) => r.url.path), [
          '/everythingllm/health',
          '/api/v1/workspace/w/thread/t/stream-chat',
        ]);
      });
    }

    test('a key the relay refuses fails the answer in its words', () async {
      final error = await _failure(
        relay(
          (_) => lines([]),
          startStatus: 403,
          start: {'error': 'No valid api key found.'},
        ).streamChat('w', 't', 'Hi').drain<void>(),
      );
      expect(error.status, 403);
    });

    test('a dropped connection rejoins after the last event seen', () async {
      final seen = <http.Request>[];
      final events = await relay(
        (attempt) => attempt == 0
            ? broken([
                chunk(1, {'type': 'textResponseChunk', 'textResponse': 'Hel'}),
              ])
            : lines([
                chunk(2, {'type': 'textResponseChunk', 'textResponse': 'lo'}),
                event(3, 'done', {}),
              ]),
        seen: seen,
      ).streamChat('w', 't', 'Hi').toList();
      expect(
        [for (final e in events.whereType<TextChunk>()) e.text].join(),
        'Hello',
      );
      final follows = seen
          .where((r) => r.url.path == '/everythingllm/v1/runs/r_1/events')
          .toList();
      expect(follows, hasLength(2));
      expect(follows.last.headers['Last-Event-ID'], '1');
    });

    test('a quiet connection is rejoined too', () async {
      final events = await relay(
        (attempt) => attempt == 0
            ? StreamController<List<int>>().stream
            : lines([
                chunk(1, {'type': 'textResponseChunk', 'textResponse': 'Hi'}),
                event(2, 'done', {}),
              ]),
        quiet: const Duration(milliseconds: 50),
      ).streamChat('w', 't', 'Hi').toList();
      expect((events.first as TextChunk).text, 'Hi');
    });

    test('a relay failing for a moment while rejoining is rejoined', () async {
      final events = await relay(
        (_) => lines([
          chunk(2, {'type': 'textResponseChunk', 'textResponse': 'Hi'}),
          event(3, 'done', {}),
        ]),
        eventsStatus: (attempt) => attempt == 0 ? 503 : 200,
      ).streamChat('w', 't', 'Hi').toList();
      expect((events.first as TextChunk).text, 'Hi');
    });

    test('an end that carries no JSON still ends the answer', () async {
      for (final end in [
        'id: 1\nevent: done\ndata:\n\n',
        'id: 1\nevent: done\ndata: ok\n\n',
      ]) {
        final seen = <http.Request>[];
        await relay(
          (_) => lines([end]),
          seen: seen,
          rejoinDelays: const [Duration.zero, Duration.zero],
        ).streamChat('w', 't', 'Hi').toList();
        expect(
          seen.where((r) => r.url.path == '/everythingllm/v1/runs/r_1/events'),
          hasLength(1),
        );
      }
    });

    test('a failed run in plain words gives those words', () async {
      final error = await _failure(
        relay(
          (_) => lines(['id: 1\nevent: failed\ndata: The model crashed.\n\n']),
        ).streamChat('w', 't', 'Hi').toList(),
      );
      expect(error.message, 'The model crashed.');
    });

    test('a run that cannot be rejoined says the answer goes on', () async {
      final error = await _failure(
        relay(
          (_) => lines([]),
          rejoinDelays: const [Duration.zero, Duration.zero],
        ).streamChat('w', 't', 'Hi').toList(),
      );
      expect(error.message, startsWith('Lost the connection to the relay.'));
    });

    test('a failed run gives the relay\'s words', () async {
      final error = await _failure(
        relay(
          (_) => lines([
            event(1, 'failed', {
              'error': 'The relay restarted during the answer.',
            }),
          ]),
        ).streamChat('w', 't', 'Hi').toList(),
      );
      expect(error.message, 'The relay restarted during the answer.');
    });

    test('a chat with a run going says so', () async {
      final error = await _failure(
        relay(
          (_) => lines([]),
          startStatus: 409,
          start: {'error': 'That thread already has an answer running.'},
        ).streamChat('w', 't', 'Hi').toList(),
      );
      expect(error.message, 'That thread already has an answer running.');
      expect(error.status, 409);
    });

    test('stop cancels the run on the relay', () async {
      final seen = <http.Request>[];
      final held = StreamController<List<int>>();
      final api = relay((_) => held.stream, seen: seen);
      final first = Completer<void>();
      final subscription = api.streamChat('w', 't', 'Hi').listen((_) {
        if (!first.isCompleted) first.complete();
      });
      held.add(
        utf8.encode(
          chunk(1, {'type': 'textResponseChunk', 'textResponse': 'H'}),
        ),
      );
      await first.future;
      await api.stopChat('w', 't');
      await subscription.cancel();
      expect(held.hasListener, isFalse);
      expect(seen.last.method, 'POST');
      expect(seen.last.url.path, '/everythingllm/v1/runs/r_1/cancel');
    });

    test(
      'stop before the relay has started the run cancels it once it has',
      () async {
        final seen = <http.Request>[];
        final started = Completer<void>();
        final api = relay(
          (_) => StreamController<List<int>>().stream,
          seen: seen,
          started: started.future,
        );
        final subscription = api.streamChat('w', 't', 'Hi').listen((_) {});
        await pumpEventQueue();
        expect(seen.last.url.path, '/everythingllm/v1/runs');
        final stopped = api.stopChat('w', 't');
        final cancelled = subscription.cancel();
        started.complete();
        await stopped;
        await cancelled;
        expect(seen.last.method, 'POST');
        expect(seen.last.url.path, '/everythingllm/v1/runs/r_1/cancel');
        expect(
          seen.where((r) => r.url.path == '/everythingllm/v1/runs/r_1/events'),
          isEmpty,
        );
      },
    );

    test('stop with no run going sends nothing', () async {
      final seen = <http.Request>[];
      await relay((_) => lines([]), seen: seen).stopChat('w', 't');
      expect(seen, isEmpty);
    });

    test('letting go of the answer leaves the run going', () async {
      final seen = <http.Request>[];
      final held = StreamController<List<int>>();
      final api = relay((_) => held.stream, seen: seen);
      final first = Completer<void>();
      final subscription = api.streamChat('w', 't', 'Hi').listen((_) {
        if (!first.isCompleted) first.complete();
      });
      held.add(
        utf8.encode(
          chunk(1, {'type': 'textResponseChunk', 'textResponse': 'H'}),
        ),
      );
      await first.future;
      await subscription.cancel();
      expect(held.hasListener, isFalse);
      await api.stopChat('w', 't');
      expect(seen.where((r) => r.url.path.endsWith('/cancel')), isEmpty);
    });
  });
}
