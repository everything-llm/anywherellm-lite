import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anywherellm/adapters/anythingllm_client.dart';
import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/embeds.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/multipart.dart';

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
  group('a chat\'s browser', () {
    const reply = {
      'tab': {
        'card': 'https://host.example.ts.net:8445/_live/browser/bw-1.jpg',
        'page': 'https://host.example.ts.net:8445/_live/browser/bw-1',
        'state': 'working',
        'title': 'Hacker News',
      },
      'logins': [],
    };

    test('is asked of the host\'s cards port with the developer key', () async {
      final seen = <http.Request>[];
      final browser = await _answering(
        reply,
        seen: seen,
      ).chatBrowser('q3', 'budget');
      expect(browser!.tab!.title, 'Hacker News');
      expect(
        seen.single.url.toString(),
        'https://host.example.ts.net:8445/_live/browser/chat/q3/budget',
      );
      expect(seen.single.headers['Authorization'], 'Bearer SECRET-KEY');
    });

    test('is nothing when the server has no such route or chat', () async {
      for (final status in [404, 403, 502]) {
        final api = _api((_) async => http.Response('No such chat.', status));
        expect(
          await api.chatBrowser('q3', 'budget'),
          isNull,
          reason: '$status',
        );
      }
      final api = _api((_) async => http.Response('<html></html>', 200));
      expect(await api.chatBrowser('q3', 'budget'), isNull);
      final unreachable = _api((_) async => throw http.ClientException('no'));
      expect(await unreachable.chatBrowser('q3', 'budget'), isNull);
    });

    test(
      'is nothing with no server, or over http where it is not allowed',
      () async {
        final none = _api((_) async => http.Response('{}', 200), current: null);
        expect(await none.chatBrowser('q3', 'budget'), isNull);
        final http1 = HttpAnythingLlmApi(
          holder: ConnectionHolder(
            const Connection(
              baseUrl: 'http://host.example.ts.net:3001',
              apiKey: 'K',
            ),
          ),
          allowHttp: false,
          client: MockClient((_) async => throw StateError('must not ask')),
        );
        expect(await http1.chatBrowser('q3', 'budget'), isNull);
      },
    );

    test(
      'a host with no route at all is not asked again until the relay is',
      () async {
        final seen = <http.Request>[];
        final api = _api((request) async {
          seen.add(request);
          return http.Response('<html>Not found</html>', 404);
        });
        expect(await api.chatBrowser('q3', 'budget'), isNull);
        expect(await api.chatBrowser('q3', 'other'), isNull);
        expect(seen, hasLength(1));
        // A JSON error is the route itself saying there is no such chat, so it is asked again.
        final route = _api((request) async {
          seen.add(request);
          return http.Response('{"error":"No such chat."}', 404);
        });
        await route.chatBrowser('q3', 'a');
        await route.chatBrowser('q3', 'b');
        expect(seen, hasLength(3));
      },
    );

    test(
      'its picture is asked again with the last etag, and says when unchanged',
      () async {
        final seen = <http.Request>[];
        final api = _api((request) async {
          seen.add(request);
          if (request.headers['If-None-Match'] == '"a"') {
            return http.Response('', 304);
          }
          return http.Response.bytes([1, 2, 3], 200, headers: {'etag': '"a"'});
        });
        final first = await api.browserFrame('q3', 'budget');
        expect(first!.bytes, [1, 2, 3]);
        expect(first.etag, '"a"');
        expect(
          seen.last.url.toString(),
          'https://host.example.ts.net:8445/_live/browser/chat/q3/budget/card.jpg',
        );
        expect(seen.last.headers['Accept'], 'image/jpeg');
        expect(seen.last.headers['Authorization'], 'Bearer SECRET-KEY');
        final again = await api.browserFrame('q3', 'budget', etag: first.etag);
        expect(again!.bytes, isNull);
        expect(again.etag, '"a"');
      },
    );

    test('a chat with no tab has no picture', () async {
      final api = _api((_) async => http.Response('{"error":"No tab."}', 404));
      expect(await api.browserFrame('q3', 'budget'), isNull);
    });

    test(
      'is handed back by a POST, and answers as the chat\'s browser does',
      () async {
        final seen = <http.Request>[];
        final browser = await _answering(
          reply,
          seen: seen,
        ).handBackBrowser('q3', 'budget');
        expect(browser.tab!.state, 'working');
        expect(seen.single.method, 'POST');
        expect(seen.single.url.path, '/_live/browser/chat/q3/budget/give');
      },
    );

    test('a hand back the server refuses says why', () async {
      final error = await _failure(
        _api(
          (_) async =>
              http.Response('{"error":"This chat has no browser tab."}', 404),
        ).handBackBrowser('q3', 'budget'),
      );
      expect(error.message, 'This chat has no browser tab.');
      final odd = await _failure(
        _answering({'unrelated': true}).handBackBrowser('q3', 'budget'),
      );
      expect(odd.message, contains('did not answer like the browser'));
    });
  });

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
      expect(turns.first.attachments.map((a) => a.name), ['photo.png']);
      expect(turns.last.attachments, isEmpty);
    });

    test('a history keeps the pictures sent with a question', () async {
      final turns = await _answering({
        'history': [
          {
            'role': 'user',
            'content': 'What colour?',
            'attachments': [
              {
                'name': 'teal.png',
                'mime': 'image/png',
                'contentString':
                    'data:image/png;base64,${base64Encode([1, 2, 3])}',
              },
              {
                'name': 'notes.csv',
                'mime': 'application/anythingllm-document',
                'contentString': 'data:text/csv;base64,${base64Encode([4])}',
              },
              {'name': 'bad.png', 'mime': 'image/png', 'contentString': '%%'},
            ],
          },
        ],
      }).history('w', 't');
      final sent = turns.single.attachments;
      expect(sent.map((a) => a.name), ['teal.png', 'notes.csv', 'bad.png']);
      expect(sent.map((a) => a.picture), [
        [1, 2, 3],
        isNull,
        isNull,
      ]);
    });

    test('a history turn keeps its exchange id and feedback', () async {
      final turns = await _answering({
        'history': [
          {'role': 'user', 'content': 'Q', 'chatId': 7},
          {
            'role': 'assistant',
            'content': 'A',
            'chatId': 7,
            'feedbackScore': true,
          },
          {'role': 'user', 'content': 'Old'},
        ],
      }).history('w', 't');
      expect(turns.map((t) => t.chatId), [7, 7, null]);
      expect(turns.map((t) => t.feedback), [null, true, null]);
    });

    test('a history answer keeps the files an agent made', () async {
      final turns = await _answering({
        'history': [
          {
            'role': 'assistant',
            'content': 'Here is your report.',
            'metrics': {'model': 'glm-5.3', 'outputTps': 41.8},
            'outputs': [
              {
                'type': 'PdfFileDownload',
                'payload': {
                  'filename': 'report.pdf',
                  'storageFilename': 'pdf-1f2e.pdf',
                  'fileSize': 2048,
                },
              },
              {
                'type': 'imageGenerationCard',
                'payload': {'storageFilename': 'img-9a.png', 'prompt': 'a cat'},
              },
              {
                'type': 'PdfFileDownload',
                'payload': {'filename': 'x', 'storageFilename': '../../.env'},
              },
              {
                'type': 'PdfFileDownload',
                'payload': {'filename': 'y', 'storageFilename': '..'},
              },
              {
                'type': 'rechartVisualize',
                'payload': {'data': []},
              },
            ],
          },
        ],
      }).history('w', 't');
      expect(turns.single.metrics?.text, 'glm-5.3 · 42 tok/s');
      final files = turns.single.files;
      expect(files.map((f) => (f.name, f.storageName, f.size, f.isImage)), [
        ('report.pdf', 'pdf-1f2e.pdf', 2048, false),
        ('img-9a.png', 'img-9a.png', null, true),
      ]);
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

    test('an answer that goes silent is given up after idle', () async {
      final silent = StreamController<List<int>>();
      addTearDown(silent.close);
      final api = HttpAnythingLlmApi(
        holder: ConnectionHolder(_connection),
        idle: const Duration(milliseconds: 50),
        client: _notRelay((request, body) async {
          await body.drain<void>();
          return http.StreamedResponse(silent.stream, 200);
        }),
      );
      final error = await _failure(api.streamChat('w', 't', 'Hi').drain());
      expect(error.message, contains('sent nothing for too long'));
    });

    test('a connection cut off mid-answer says so', () async {
      final api = HttpAnythingLlmApi(
        holder: ConnectionHolder(_connection),
        client: _notRelay((request, body) async {
          await body.drain<void>();
          return http.StreamedResponse(
            Stream.error(http.ClientException('Connection reset')),
            200,
          );
        }),
      );
      final error = await _failure(api.streamChat('w', 't', 'Hi').drain());
      expect(error.message, 'The answer was cut off: Connection reset');
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

    test('the closing chunk gives the exchange\'s id', () async {
      final events = await streaming([
        data({'type': 'textResponseChunk', 'textResponse': 'Hi'}),
        data({
          'type': 'finalizeResponseStream',
          'close': true,
          'error': false,
          'chatId': 42,
        }),
      ]).streamChat('w', 't', 'Hi').toList();
      expect((events.last as ChatDone).chatId, 42);
    });

    test('an agent\'s closing chunk hands on the files it made', () async {
      final events = await streaming([
        data({'type': 'textResponse', 'textResponse': 'Made it.'}),
        data({
          'type': 'finalizeResponseStream',
          'textResponse': 'Made it.',
          'sources': [],
          'close': true,
          'error': false,
          'metrics': {'model': 'glm-5.3', 'completion_tokens': 12},
          'outputs': [
            {
              'type': 'imageGenerationCard',
              'payload': {
                'filename': 'cat.png',
                'storageFilename': 'img-1.png',
                'fileSize': 900,
                'url': '/v1/document/generated-files/img-1.png',
              },
            },
          ],
        }),
      ]).streamChat('w', 't', 'Draw a cat').toList();
      final done = events.last as ChatDone;
      expect(done.metrics?.text, 'glm-5.3 · 12 tokens');
      expect(done.files.single.name, 'cat.png');
      expect(done.files.single.isImage, isTrue);
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
          'text \n\nHead',
          'whole <think>Pick.</think>Headline: [x](https://x.test)',
          'done [A story https://x.test/story, Another null]',
        ],
      );
    });

    test('a browser skill call is a browser step in words', () async {
      final events = await streaming([
        data({
          'id': 'a',
          'type': 'agentThought',
          'thought':
              '@agent is executing `browser-act` tool {\n  "action": "fill",\n'
              '  "ref": "e1",\n  "text": "Scratch Test"\n}',
          'close': false,
          'error': null,
        }),
        data({
          'id': 'a',
          'type': 'agentThought',
          'thought':
              '@agent is executing `web-browsing` tool {\n  "query": "news"\n}',
          'close': false,
          'error': null,
        }),
        data({
          'uuid': 'a',
          'type': 'finalizeResponseStream',
          'textResponse': 'Filled.',
          'sources': [],
          'close': true,
          'error': false,
        }),
      ]).streamChat('w', 't', 'Fill it').toList();
      final statuses = events.whereType<StatusChunk>().toList();
      expect(
        [for (final s in statuses) (s.text, s.tool)],
        [
          ('Typing into a field', 'browser-act'),
          ('Running web-browsing', 'web-browsing'),
        ],
      );
    });

    test('text after a tool starts a new paragraph, unless spaced', () async {
      Map<String, Object?> piece(String text) => {
        'type': 'textResponseChunk',
        'textResponse': text,
      };
      Map<String, Object?> thought(String text) => {
        'type': 'agentThought',
        'thought': text,
      };
      final events = await streaming([
        data(piece('Kept it private.')),
        data(thought('@agent: Running write-file')),
        data(piece('Done.')),
        data(thought('@agent: Running browse')),
        data(piece(' Opened it.')),
        data({'type': 'finalizeResponseStream', 'close': true}),
      ]).streamChat('w', 't', 'Hi').toList();
      expect(
        [
          for (final e in events)
            if (e case TextChunk(:final text)) text,
        ],
        ['Kept it private.', '\n\nDone.', ' Opened it.'],
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

    test(
      'stopping before the first chunk lets go of the answer at once',
      () async {
        final body = StreamController<List<int>>();
        final api = HttpAnythingLlmApi(
          holder: ConnectionHolder(_connection),
          client: MockClient.streaming((request, _) async {
            if (request.url.path == '/everythingllm/health') {
              return http.StreamedResponse(
                Stream.value(utf8.encode('no')),
                404,
              );
            }
            return http.StreamedResponse(body.stream, 200);
          }),
        );
        final subscription = api.streamChat('w', 't', 'Hi').listen(null);
        await pumpEventQueue();
        expect(body.hasListener, isTrue);
        await subscription.cancel().timeout(const Duration(seconds: 1));
        expect(body.hasListener, isFalse);
        await body.close();
      },
    );

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

  group('scheduled jobs', () {
    test('reads them from the web route, signed in', () async {
      final server = _SignInServer()
        ..routes['/api/scheduled-jobs'] = {
          'jobs': [
            {
              'name': 'Morning brief',
              'schedule': '0 7 * * *',
              'enabled': true,
              'nextRunAt': '2026-10-09T07:00:00Z',
            },
          ],
        };
      final jobs = await server.api().scheduledJobs();
      expect(server.seen.last.url.path, '/api/scheduled-jobs');
      expect(server.seen.last.headers['Authorization'], 'Bearer TOKEN-1');
      expect(jobs.single.name, 'Morning brief');
      expect(jobs.single.nextRun, DateTime.utc(2026, 10, 9, 7));
    });

    test('a protected server without a saved password asks for one', () async {
      final server = _SignInServer();
      final error = await _failure(server.api(password: null).scheduledJobs());
      expect(error.status, 401);
      expect(error.message, contains('Add it in Settings'));
    });
  });

  group('slash commands', () {
    test('reads the presets from the system route, signed in', () async {
      final server = _SignInServer()
        ..routes['/api/system/slash-command-presets'] = {
          'presets': [
            {
              'id': 1,
              'command': '/deep-research',
              'prompt': '@agent Research:',
              'description': 'Research in depth',
            },
            {'id': 2, 'command': 'broken'},
          ],
        };
      final presets = await server.api().slashCommands();
      expect(server.seen.map((r) => r.url.path), [
        '/api/request-token',
        '/api/system/slash-command-presets',
      ]);
      expect(jsonDecode(server.seen.first.body), {'password': 'PASS-WORD'});
      expect(server.seen.last.headers['Authorization'], 'Bearer TOKEN-1');
      expect([for (final p in presets) p.command], ['/deep-research']);
      expect(presets.single.description, 'Research in depth');
    });

    test('a protected server without a saved password asks for one', () async {
      final server = _SignInServer();
      final error = await _failure(server.api(password: null).slashCommands());
      expect(error.status, 401);
      expect(error.message, contains('Add it in Settings'));
      expect(server.seen.single.url.path, '/api/system/slash-command-presets');
      expect(server.seen.single.headers.containsKey('Authorization'), isFalse);
    });

    test(
      'a password-free server lists its presets without signing in',
      () async {
        final api = _api((request) async {
          expect(request.url.path, '/api/system/slash-command-presets');
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response(
            jsonEncode({
              'presets': [
                {'id': 1, 'command': '/brief', 'prompt': 'Be brief:'},
              ],
            }),
            200,
          );
        }, current: _connection.withPassword(null));
        expect((await api.slashCommands()).single.command, '/brief');
      },
    );
  });

  group('signed in', () {
    test('signs in once and keeps the token for later calls', () async {
      final server = _SignInServer()
        ..routes['/api/system/slash-command-presets'] = {'presets': []};
      final api = server.api();
      await api.slashCommands();
      await api.slashCommands();
      expect(
        server.seen.where((r) => r.url.path == '/api/request-token'),
        hasLength(1),
      );
    });

    test('a token the server refuses is replaced once', () async {
      final server = _SignInServer()
        ..routes['/api/system/slash-command-presets'] = {'presets': []};
      final api = server.api();
      await api.slashCommands();
      server.valid = 'none';
      await api.slashCommands();
      expect(server.seen.map((r) => r.url.path).toList(), [
        '/api/request-token',
        '/api/system/slash-command-presets',
        '/api/system/slash-command-presets',
        '/api/request-token',
        '/api/system/slash-command-presets',
      ]);
      expect(server.seen.last.headers['Authorization'], 'Bearer TOKEN-2');
    });

    test('a wrong password is refused in plain words', () async {
      final server = _SignInServer();
      final error = await _failure(
        server.api().signIn(_connection.withPassword('WRONG')),
      );
      expect(error.status, 403);
      expect(error.message, 'The server did not accept the password.');
    });

    test('a call that takes the login never sends the key', () async {
      final server = _SignInServer()
        ..routes['/api/workspace/w/thread/t/delete-edited-chats'] = 'OK'
        ..routes['/api/workspace/w/chat-feedback/7'] = {'success': true};
      final api = server.api();
      await api.dropFrom('w', 't', 7);
      await api.setFeedback('w', 7, true);
      for (final request in server.seen) {
        expect(request.headers['Authorization'], isNot(contains('SECRET-KEY')));
      }
      final drop = server.seen.firstWhere(
        (r) => r.url.path.endsWith('delete-edited-chats'),
      );
      expect(drop.method, 'DELETE');
      expect(jsonDecode(drop.body), {'startingId': 7});
      expect(jsonDecode(server.seen.last.body), {'feedback': true});
    });

    test('no error message carries the password or the token', () async {
      final server = _SignInServer()
        ..routes['/api/system/slash-command-presets'] = {'error': 'boom'}
        ..status = 500;
      final api = server.api();
      final error = await _failure(api.slashCommands());
      expect(error.message, isNot(contains('PASS-WORD')));
      expect(error.message, isNot(contains('TOKEN')));
      final refused = await _failure(
        api.signIn(_connection.withPassword('PASS-WRONG')),
      );
      expect(refused.message, isNot(contains('PASS-WRONG')));
    });

    group('a key from the password', () {
      const base = 'https://host.example.ts.net:3001';

      test('reuses the key named AnywhereLLM', () async {
        final server = _SignInServer()
          ..routes['/api/system/api-keys'] = {
            'apiKeys': [
              {'id': 1, 'name': 'Laptop', 'secret': 'OTHER'},
              {'id': 2, 'name': 'AnywhereLLM', 'secret': 'SHARED-KEY'},
            ],
            'error': null,
          };
        final key = await server.api().issueKey(base, password: 'PASS-WORD');
        expect(key, 'SHARED-KEY');
        expect(server.seen.map((r) => r.url.path), [
          '/api/request-token',
          '/api/system/api-keys',
        ]);
        expect(server.seen.last.headers['Authorization'], 'Bearer TOKEN-1');
      });

      test('makes one named AnywhereLLM when there is none', () async {
        final server = _SignInServer()
          ..routes['/api/system/api-keys'] = {
            'apiKeys': [
              {'id': 1, 'name': null, 'secret': 'UNNAMED'},
              {'id': 2, 'name': 'AnywhereLLM', 'secret': ''},
            ],
          }
          ..routes['/api/system/generate-api-key'] = {
            'apiKey': {'id': 3, 'name': 'AnywhereLLM', 'secret': 'NEW-KEY'},
            'error': null,
          };
        final key = await server.api().issueKey(base, password: 'PASS-WORD');
        expect(key, 'NEW-KEY');
        final made = server.seen.last;
        expect(made.method, 'POST');
        expect(made.url.path, '/api/system/generate-api-key');
        expect(jsonDecode(made.body), {'name': 'AnywhereLLM'});
      });

      test('a key the server does not make says so', () async {
        final server = _SignInServer()
          ..routes['/api/system/api-keys'] = {'apiKeys': []}
          ..routes['/api/system/generate-api-key'] = {
            'apiKey': null,
            'error': 'disk full',
          };
        final error = await _failure(
          server.api().issueKey(base, password: 'PASS-WORD'),
        );
        expect(error.message, 'disk full');
      });

      test('an open server is asked without credentials', () async {
        final seen = <http.Request>[];
        final api = _api((request) async {
          seen.add(request);
          return http.Response(
            jsonEncode(
              request.url.path == '/api/system/api-keys'
                  ? {'apiKeys': []}
                  : {
                      'apiKey': {'name': 'AnywhereLLM', 'secret': 'OPEN-KEY'},
                    },
            ),
            200,
          );
        }, current: null);
        expect(await api.issueKey(base), 'OPEN-KEY');
        for (final request in seen) {
          expect(request.headers.containsKey('Authorization'), isFalse);
        }
      });

      test('a server that wants a password says so', () async {
        final server = _SignInServer();
        final error = await _failure(server.api().issueKey(base));
        expect(error.status, 401);
        expect(
          error.message,
          'This needs the server password. Add it in Settings.',
        );
      });

      test('a wrong password is refused without being repeated', () async {
        final server = _SignInServer();
        final error = await _failure(
          server.api().issueKey(base, password: 'PASS-WRONG'),
        );
        expect(error.message, 'The server did not accept the password.');
        expect(error.message, isNot(contains('PASS-WRONG')));
        expect(server.seen.map((r) => r.url.path), ['/api/request-token']);
      });

      test('an http address fails before the password is sent', () async {
        var sent = 0;
        final api = HttpAnythingLlmApi(
          holder: ConnectionHolder(),
          allowHttp: false,
          client: MockClient((_) async {
            sent++;
            return http.Response('{}', 200);
          }),
        );
        final error = await _failure(
          api.issueKey('http://h:3001', password: 'PASS-WORD'),
        );
        expect(error.message, contains('https://'));
        expect(sent, 0);
      });
    });

    test('asks how the server signs in without the key', () async {
      final seen = <http.Request>[];
      Future<ServerAuth> ask(Map<String, Object?> results) =>
          _answering({'results': results}, seen: seen).serverAuth(_connection);
      expect(
        await ask({'RequiresAuth': true, 'MultiUserMode': false}),
        ServerAuth.password,
      );
      expect(await ask({'RequiresAuth': false}), ServerAuth.none);
      expect(
        await ask({'RequiresAuth': true, 'MultiUserMode': true}),
        ServerAuth.multiUser,
      );
      expect(seen.first.url.path, '/api/setup-complete');
      expect(seen.first.headers.containsKey('Authorization'), isFalse);
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
              Attachment.of('photo.PNG', Uint8List.fromList([1, 2, 3])),
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
        attachmentJson(
          Attachment.of('notes.xyz', Uint8List(1)),
        )['contentString'],
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

    test(
      'a settings change posts the keys, and every key must come back written',
      () async {
        final seen = <http.Request>[];
        await _answering({
          'newValues': {'GenericOpenAiModelPref': 'glm-5.3'},
          'error': null,
        }, seen: seen).updateSystem({'GenericOpenAiModelPref': 'glm-5.3'});
        expect(seen.single.url.path, '/api/v1/system/update-env');
        expect(jsonDecode(seen.single.body), {
          'GenericOpenAiModelPref': 'glm-5.3',
        });

        final dropped = await _failure(
          _answering({'newValues': {}, 'error': null})
              .updateSystem({'MadeUpKey': '1'}),
        );
        expect(dropped.message, 'The server did not write MadeUpKey.');
        final refused = await _failure(
          _answering({'newValues': {}, 'error': 'Invalid base path'})
              .updateSystem({'OllamaLLMBasePath': 'nope'}),
        );
        expect(refused.message, 'Invalid base path');
      },
    );

    test('embeds are listed, made, changed and deleted by uuid', () async {
      final seen = <http.Request>[];
      final api = _api((request) async {
        seen.add(request);
        return http.Response(switch (request.url.path) {
          '/api/v1/embed' => jsonEncode({
            'embeds': [
              {
                'uuid': 'e-1',
                'workspace': {'name': 'Q3'},
                'chat_count': 2,
              },
            ],
          }),
          '/api/v1/embed/new' => jsonEncode({
            'embed': {'uuid': 'e-2'},
            'error': null,
          }),
          '/api/v1/embed/e-1/chats' => jsonEncode({
            'chats': [
              {'prompt': 'Hi', 'response': '{"text":"Hello"}'},
            ],
          }),
          _ => jsonEncode({'success': true, 'error': null}),
        }, 200);
      });
      expect((await api.embeds()).single.chats, 2);
      expect(await api.createEmbed(const NewEmbed(workspaceSlug: 'q3')), 'e-2');
      await api.updateEmbed('e-1', enabled: false);
      await api.deleteEmbed('e-1');
      expect((await api.embedChats('e-1')).single.answer, 'Hello');
      expect(seen.map((r) => '${r.method} ${r.url.path}'), [
        'GET /api/v1/embed',
        'POST /api/v1/embed/new',
        'POST /api/v1/embed/e-1',
        'DELETE /api/v1/embed/e-1',
        'GET /api/v1/embed/e-1/chats',
      ]);
      expect(jsonDecode(seen[2].body), {'enabled': false});
    });

    test('an embed the server would not make says why', () async {
      final error = await _failure(
        _answering({'embed': null, 'error': 'Workspace not found'})
            .createEmbed(const NewEmbed(workspaceSlug: 'gone')),
      );
      expect(error.message, 'Workspace not found');
    });

    test('the vector count is the server\'s number', () async {
      final seen = <http.Request>[];
      expect(
        await _answering({'vectorCount': 796}, seen: seen).vectorCount(),
        796,
      );
      expect(seen.single.url.path, '/api/v1/system/vector-count');
      await _failure(_answering({'vectorCount': 'many'}).vectorCount());
    });

    test(
      'the chat log reads a page of chats and whether more follow',
      () async {
        final seen = <http.Request>[];
        final log = await _answering({
          'chats': [
            {
              'id': 7,
              'prompt': 'When is the boiler due?',
              'response': '{"text":"In May.","sources":[]}',
              'createdAt': '2026-10-06T09:15:00.000Z',
              'workspace': {'name': 'Household', 'slug': 'household'},
              'user': {'username': 'API'},
            },
            {'id': 8, 'prompt': 'Hi', 'response': 'plain'},
          ],
          'hasPages': true,
        }, seen: seen).workspaceChats(page: 2);
        expect(seen.single.url.path, '/api/v1/admin/workspace-chats');
        expect(jsonDecode(seen.single.body), {'offset': 2});
        expect(log.more, isTrue);
        final first = log.chats.first;
        expect(
          (first.workspace, first.question),
          ('Household', 'When is the boiler due?'),
        );
        expect(first.at, DateTime.utc(2026, 10, 6, 9, 15));
        expect((log.chats.last.question, log.chats.last.workspace), ('Hi', ''));
      },
    );

    test('the relay is found by its health check, once', () async {
      var asked = 0;
      final api = _api((request) async {
        if (request.url.path == '/everythingllm/health') asked++;
        return http.Response(
          jsonEncode({
            'service': 'everythingllm',
            'features': ['runs'],
          }),
          200,
        );
      });
      expect(await api.relayFound(), isTrue);
      expect(await api.relayFound(), isTrue);
      expect(asked, 1);
      expect(
        await _api((request) async => http.Response('<!doctype html>', 200))
            .relayFound(),
        isFalse,
      );
    });

    test('a generated file is its bytes, by its storage name', () async {
      final seen = <http.Request>[];
      final bytes = await _api((request) async {
        seen.add(request);
        return http.Response.bytes(
          [37, 80, 68, 70],
          200,
          headers: {'content-type': 'application/pdf'},
        );
      }).generatedFile('pdf-1f2e.pdf');
      expect(
        seen.single.url.path,
        '/api/v1/document/generated-files/pdf-1f2e.pdf',
      );
      expect(seen.single.headers['Authorization'], 'Bearer SECRET-KEY');
      expect(bytes, [37, 80, 68, 70]);
      final gone = await _failure(
        _answering({
          'error': 'File not found',
        }, status: 404).generatedFile('pdf-0.pdf'),
      );
      expect(gone.message, contains('File not found'));
    });

    test(
      'a generated HTML file is its bytes, and the web UI\'s page is not',
      () async {
        HttpAnythingLlmApi page({required bool attached}) => _api(
          (request) async => http.Response(
            '<!doctype html><p>Made</p>',
            200,
            headers: {
              'content-type': 'text/html; charset=utf-8',
              if (attached)
                'content-disposition': 'attachment; filename="page.html"',
            },
          ),
        );
        expect(
          utf8.decode(await page(attached: true).generatedFile('page-1.html')),
          '<!doctype html><p>Made</p>',
        );
        await _failure(page(attached: false).generatedFile('page-1.html'));
      },
    );

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
          'anythingllm-chats.csv',
          'anythingllm-chats.json',
          'anythingllm-chats.jsonl',
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
      Object? running,
      int runningStatus = 200,
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
          if (path == '/everythingllm/v1/runs' && request.method == 'GET') {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(running ?? {'runs': []}))),
              runningStatus,
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

    test('a relay gone from its route is asked about again', () async {
      final seen = <http.Request>[];
      final api = relay((_) => lines([]), seen: seen, startStatus: 502);
      await _failure(api.streamChat('w', 't', 'Hi').drain<void>());
      await _failure(api.streamChat('w', 't', 'Again').drain<void>());
      expect(
        seen.where((r) => r.url.path == '/everythingllm/health'),
        hasLength(2),
      );
    });

    test('asked again, the relay is checked afresh', () async {
      final seen = <http.Request>[];
      final api = relay((_) => lines([]), seen: seen);
      expect(await api.relayFound(), isTrue);
      expect(await api.relayFound(), isTrue);
      expect(await api.relayFound(again: true), isTrue);
      expect(
        seen.where((r) => r.url.path == '/everythingllm/health'),
        hasLength(2),
      );
    });

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
              Attachment.of('photo.png', Uint8List.fromList([1, 2, 3])),
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

    test('in a browser, a health check that fails to send is remembered as no relay', () async {
      final paths = <String>[];
      final api = HttpAnythingLlmApi(
        holder: ConnectionHolder(_connection),
        browserOrigin: 'http://localhost:8080',
        client: MockClient.streaming((request, body) async {
          await body.drain<void>();
          paths.add(request.url.path);
          if (request.url.path == '/everythingllm/health') {
            throw http.ClientException('Failed to fetch');
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
    });

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
      expect(error, isA<AnswerStillRunning>());
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
      expect(error, isA<AlreadyAnswering>());
    });

    group('rejoining a running answer', () {
      Map<String, Object?> listed(
        String id, {
        String workspace = 'w',
        String thread = 't',
        Object? more,
      }) => {
        'id': id,
        'workspace': workspace,
        'thread': thread,
        'status': 'running',
        if (more is Map<String, Object?>) ...more,
      };

      Future<List<ChatEvent>> events(RejoinedAnswer found) =>
          found.events.toList();

      test(
        'lists the running runs and follows the chat\'s from the start',
        () async {
          final seen = <http.Request>[];
          final api = relay(
            (_) => lines([
              chunk(1, {'type': 'textResponseChunk', 'textResponse': 'Kept '}),
              chunk(2, {'type': 'textResponseChunk', 'textResponse': 'going'}),
              event(3, 'done', {}),
            ]),
            seen: seen,
            running: {
              'runs': [
                listed('r_9', thread: 'other'),
                listed(
                  'r_1',
                  more: {
                    'body': {'message': 'The question?'},
                  },
                ),
              ],
            },
          );
          final found = await api.rejoinChat('w', 't');
          expect(found!.question, 'The question?');
          final got = await events(found);
          expect(
            got.whereType<TextChunk>().map((c) => c.text).join(),
            'Kept going',
          );
          final list = seen.firstWhere(
            (r) => r.url.path == '/everythingllm/v1/runs',
          );
          expect(list.method, 'GET');
          expect(list.url.queryParameters, {'status': 'running'});
          final follow = seen.firstWhere(
            (r) => r.url.path == '/everythingllm/v1/runs/r_1/events',
          );
          expect(follow.headers.containsKey('Last-Event-ID'), isFalse);
        },
      );

      test(
        'reads a bare list of runs, and a question beside the run',
        () async {
          final api = relay(
            (_) => lines([event(1, 'done', {})]),
            running: [
              listed('r_1', more: {'message': 'Asked beside'}),
            ],
          );
          expect((await api.rejoinChat('w', 't'))!.question, 'Asked beside');
        },
      );

      test(
        'lists every kept run with its question, why it failed and when',
        () async {
          final seen = <http.Request>[];
          final api = relay(
            (_) => lines([]),
            seen: seen,
            running: {
              'runs': [
                listed(
                  'r_1',
                  more: {'question': '  Why?  ', 'createdAt': 1000},
                ),
                listed(
                  'r_2',
                  more: {
                    'status': 'failed',
                    'question': 'When?',
                    'error': 'The relay restarted during the answer.',
                    'createdAt': '2026-10-08T12:00:00Z',
                    'finishedAt': '2026-10-08T12:01:00Z',
                  },
                ),
                listed('r_3', more: {'question': '/reset', 'status': 'done'}),
                {'id': 'r_4', 'status': 'done'},
              ],
            },
          );
          final runs = await api.relayRuns();
          expect(
            [for (final r in runs) (r.id, r.status, r.question, r.error)],
            [
              ('r_1', 'running', 'Why?', null),
              (
                'r_2',
                'failed',
                'When?',
                'The relay restarted during the answer.',
              ),
            ],
          );
          expect(runs.first.started, DateTime.utc(1970, 1, 1, 0, 0, 1));
          expect(runs.last.finished, DateTime.utc(2026, 10, 8, 12, 1));
          final list = seen.firstWhere(
            (r) => r.url.path == '/everythingllm/v1/runs',
          );
          expect(list.url.queryParameters, isEmpty);
        },
      );

      test('a server with no relay says so rather than listing none', () async {
        final api = relay((_) => lines([]), health: {'service': 'other'});
        await expectLater(
          api.relayRuns(),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              contains('no everythingllm relay'),
            ),
          ),
        );
      });

      test('cancels a run by its id, whichever chat it answers', () async {
        final seen = <http.Request>[];
        await relay((_) => lines([]), seen: seen).cancelRun('r_1');
        final cancel = seen.single;
        expect(cancel.method, 'POST');
        expect(cancel.url.path, '/everythingllm/v1/runs/r_1/cancel');
      });

          running: {
            'runs': [
              listed(
                'r_1',
                more: {
                  'body': {'reset': true},
                },
              ),
            ],
          },
        );
        expect(await api.rejoinChat('w', 't'), isNull);
      });

      test('a server that is not a relay is not asked', () async {
        final seen = <http.Request>[];
        final api = relay(
          (_) => lines([]),
          seen: seen,
          health: {'service': 'other'},
          running: {
            'runs': [listed('r_1')],
          },
        );
        expect(await api.rejoinChat('w', 't'), isNull);
        expect(
          seen.where((r) => r.url.path == '/everythingllm/v1/runs'),
          isEmpty,
        );
      });

      test('a list that fails, or is not there, is no answer', () async {
        expect(
          await relay(
            (_) => lines([]),
            runningStatus: 500,
          ).rejoinChat('w', 't'),
          isNull,
        );
        expect(
          await relay(
            (_) => lines([]),
            runningStatus: 404,
          ).rejoinChat('w', 't'),
          isNull,
        );
        expect(
          await relay(
            (_) => lines([]),
            running: 'nonsense',
          ).rejoinChat('w', 't'),
          isNull,
        );
      });

      test('a message refused with 409 leaves the chat\'s run to be found and stopped', () async {
        final seen = <http.Request>[];
        final held = StreamController<List<int>>();
        final api = relay(
          (_) => held.stream,
          seen: seen,
          startStatus: 409,
          start: {'error': 'That thread already has an answer running.'},
          running: {
            'runs': [
              listed(
                'r_1',
                more: {
                  'body': {'message': 'Asked on the phone'},
                },
              ),
            ],
          },
        );
        await _failure(api.streamChat('w', 't', 'Hi').drain<void>());
        final found = await api.rejoinChat('w', 't');
        expect(found!.question, 'Asked on the phone');
        final first = Completer<void>();
        final subscription = found.events.listen((_) {
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
        expect(seen.last.method, 'POST');
        expect(seen.last.url.path, '/everythingllm/v1/runs/r_1/cancel');
      });

      test('stop cancels a run found again', () async {
        final seen = <http.Request>[];
        final held = StreamController<List<int>>();
        final api = relay(
          (_) => held.stream,
          seen: seen,
          running: {
            'runs': [listed('r_1')],
          },
        );
        final found = await api.rejoinChat('w', 't');
        final first = Completer<void>();
        final subscription = found!.events.listen((_) {
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

  group('answerImage', () {
    final card = Uri.parse(
      'https://host.example.ts.net:8445/_live/run/r-1.png',
    );

    /// A client that answers [body] as [type] once [headers] completes, recording each
    /// request in [seen].
    HttpAnythingLlmApi images(
      Stream<List<int>> body, {
      String type = multipartType,
      int status = 200,
      Future<void>? headers,
      List<http.BaseRequest>? seen,
      bool allowHttp = true,
    }) => HttpAnythingLlmApi(
      holder: ConnectionHolder(_connection.withPassword('PASS-WORD')),
      allowHttp: allowHttp,
      client: MockClient.streaming((request, _) async {
        seen?.add(request);
        await headers;
        return http.StreamedResponse(
          body,
          status,
          headers: {'content-type': type},
        );
      }),
    );

    test('reads each frame, with no key, password or token', () async {
      final seen = <http.BaseRequest>[];
      final api = images(Stream.value(multipart(['one', 'two'])), seen: seen);
      final frames = await api.answerImage(card).toList();
      expect(frames.map(ascii.decode), ['one', 'two']);
      expect(seen.single.url, card);
      expect(seen.single.method, 'GET');
      expect(
        seen.single.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(seen.single.headers.values.join(), isNot(contains('SECRET-KEY')));
    });

    test('refuses plain http when this device does not allow it', () async {
      final seen = <http.BaseRequest>[];
      final api = images(const Stream.empty(), seen: seen, allowHttp: false);
      final error = await _failure(
        api
            .answerImage(Uri.parse('http://host.example.ts.net:8445/a.png'))
            .drain<void>(),
      );
      expect(error.message, contains('plain http'));
      expect(seen, isEmpty);
    });

    test('a missing image fails in plain words', () async {
      final api = images(
        Stream.value(ascii.encode('No such run.')),
        status: 404,
      );
      final error = await _failure(api.answerImage(card).drain<void>());
      expect(
        error.message,
        'The image could not be read: the server answered 404.',
      );
    });

    test('cancelling lets go of the response', () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final first = Completer<void>();
      final reading = images(body.stream)
          .answerImage(card)
          .listen((_) => first.complete());
      body.add(multipart(['one'], closed: false));
      await first.future;
      await reading.cancel();
      expect(cancelled, isTrue);
    });

    test(
      'cancelling before the headers come lets go of them when they do',
      () async {
        var cancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        final headers = Completer<void>();
        final reading = images(
          body.stream,
          headers: headers.future,
        ).answerImage(card).listen((_) => fail('no frame expected'));
        await pumpEventQueue();
        await reading.cancel();
        headers.complete();
        await pumpEventQueue();
        expect(cancelled, isTrue);
      },
    );
  });
}

/// AnythingLLM's web-UI login: `request-token` takes `PASS-WORD` and hands out `TOKEN-1`,
/// `TOKEN-2` and so on, and each route in [routes] answers its body to the token in [valid]
/// alone, and 401 to anything else. Every request goes into [seen].
class _SignInServer {
  final Map<String, Object> routes = {};
  final List<http.Request> seen = [];
  int status = 200;
  String valid = '';
  var _made = 0;

  HttpAnythingLlmApi api({String? password = 'PASS-WORD'}) => _api((
    request,
  ) async {
    seen.add(request);
    if (request.url.path == '/api/request-token') {
      final given = (jsonDecode(request.body) as Map)['password'];
      if (given != 'PASS-WORD') {
        return http.Response(
          jsonEncode({'valid': false, 'token': null, 'message': 'no'}),
          200,
        );
      }
      valid = 'TOKEN-${++_made}';
      return http.Response(jsonEncode({'valid': true, 'token': valid}), 200);
    }
    if (request.headers['Authorization'] != 'Bearer $valid') {
      return http.Response(jsonEncode({'error': 'Invalid auth'}), 401);
    }
    final body = routes[request.url.path];
    if (body == null) return http.Response('Not Found', 404);
    return http.Response(body is String ? body : jsonEncode(body), status);
  }, current: _connection.withPassword(password));
}
