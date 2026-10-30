import 'dart:typed_data';
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
        (_) async => throw const FormatException(
          'Invalid HTTP header field value: "Bearer SECRET-KEY"',
        ),
      ];
      for (final handler in handlers) {
        final error = await _failure(_api(handler).verify(_connection));
        expect(error.message, isNot(contains('SECRET-KEY')));
      }
    });

    test('a key the headers refuse fails without the key', () async {
      const odd = Connection(
        baseUrl: 'https://host.example.ts.net:3001',
        apiKey: 'SECRET\u200bKEY',
      );
      final error = await _failure(
        _api(
          (request) async => throw FormatException(
            'Invalid HTTP header field value: "${request.headers['Authorization']}"',
          ),
          current: odd,
        ).verify(odd),
      );
      expect(error.message, isNot(contains('SECRET')));
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
    const plain = Connection(
      baseUrl: 'http://ai.example.com:3001',
      apiKey: 'SECRET-KEY',
    );

    test('an http address fails before the key is sent', () async {
      var sent = 0;
      final api = HttpAnythingLlmApi(
        holder: ConnectionHolder(plain),
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

    test(
      'a saved http connection fails before a delete sends the key',
      () async {
        var sent = 0;
        final api = HttpAnythingLlmApi(
          holder: ConnectionHolder(_connection),
          client: MockClient((_) async {
            sent++;
            return http.Response('', 200);
          }),
        );
        final error = await _failure(api.deleteThread('w', 't', on: plain));
        expect(error.message, contains('https://'));
        expect(sent, 0);
      },
    );

    test('an https address is used', () async {
      final api = HttpAnythingLlmApi(
        holder: ConnectionHolder(_connection),
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

  group('library', () {
    test('lists each folder with its documents and their details', () async {
      final seen = <http.Request>[];
      final folders = await _answering({
        'localFiles': {
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
                  'url': 'file:///app/collector/hotdir/notes.md',
                  'title': 'Meeting notes',
                  'chunkSource': '',
                  'published': '1/16/2024, 3:07:00 PM',
                  'wordCount': 93,
                  'pinnedWorkspaces': [],
                },
                {
                  'name': 'url-example.com-9a.json',
                  'type': 'file',
                  'url': 'file://example_com.html',
                  'title': 'example_com.html',
                  'chunkSource': 'link://https://example.com/',
                  'wordCount': '12',
                },
                {'type': 'file'},
              ],
            },
            {'name': 'Manuals', 'type': 'folder', 'items': []},
          ],
        },
      }, seen: seen).libraryFolders();
      expect(seen.single.url.path, '/api/v1/documents');
      expect(folders.map((f) => (f.name, f.docs.length)), [
        ('custom-documents', 2),
        ('Manuals', 0),
      ]);
      final [notes, page] = folders.first.docs;
      expect(
        (notes.path, notes.title, notes.words, notes.web, notes.link),
        (
          'custom-documents/notes.md-1f2e.json',
          'Meeting notes',
          93,
          false,
          null,
        ),
      );
      expect(notes.fileName, 'notes.md');
      expect(notes.published, '1/16/2024, 3:07:00 PM');
      expect(
        (page.web, page.link, page.words),
        (true, 'https://example.com/', 12),
      );
    });

    test('a folder listed without its documents is read on its own', () async {
      final seen = <http.Request>[];
      final folders = await _api((request) async {
        seen.add(request);
        return http.Response(
          jsonEncode(
            request.url.path == '/api/v1/documents'
                ? {
                    'localFiles': {
                      'items': [
                        {'name': 'Bills and papers', 'type': 'folder'},
                      ],
                    },
                  }
                : {
                    'folder': 'Bills and papers',
                    'documents': [
                      {'name': 'lease.docx-3.json', 'type': 'file'},
                    ],
                  },
          ),
          200,
        );
      }).libraryFolders();
      expect(seen.map((r) => r.url.path), [
        '/api/v1/documents',
        '/api/v1/documents/folder/Bills%20and%20papers',
      ]);
      expect(
        folders.single.docs.single.path,
        'Bills and papers/lease.docx-3.json',
      );
      expect(folders.single.docs.single.title, 'lease.docx-3.json');
    });

    test('an upload into a folder names it in the path', () async {
      final seen = <http.Request>[];
      await _answering({
        'success': true,
        'documents': [],
      }, seen: seen).upload('a.md', const [1], folder: 'Bills and papers');
      expect(
        seen.single.url.path,
        '/api/v1/document/upload/Bills%20and%20papers',
      );
    });

    test('a folder is made by name', () async {
      final seen = <http.Request>[];
      await _answering({
        'success': true,
        'message': null,
      }, seen: seen).createFolder('Manuals');
      expect(seen.single.method, 'POST');
      expect(seen.single.url.path, '/api/v1/document/create-folder');
      expect(jsonDecode(seen.single.body), {'name': 'Manuals'});
    });

    test(
      'a folder already there is refused with the server\'s words',
      () async {
        final error = await _failure(
          _answering({
            'success': false,
            'message': 'Folder by that name already exists',
          }, status: 500).createFolder('Manuals'),
        );
        expect(error.message, 'Folder by that name already exists');
      },
    );

    test('a move posts each document from one path to another', () async {
      final seen = <http.Request>[];
      await _answering({
        'success': true,
        'message': null,
      }, seen: seen).moveDocuments([
        (from: 'custom-documents/a.json', to: 'Manuals/a.json'),
      ]);
      expect(seen.single.url.path, '/api/v1/document/move-files');
      expect(jsonDecode(seen.single.body), {
        'files': [
          {'from': 'custom-documents/a.json', 'to': 'Manuals/a.json'},
        ],
      });
    });

    test(
      'a move the server leaves undone is a failure that says why',
      () async {
        final error = await _failure(
          _answering({
            'success': true,
            'message': '1/1 files not moved. Unembed them from all workspaces.',
          }).moveDocuments([(from: 'a/b.json', to: 'c/b.json')]),
        );
        expect(error.message, notMoved);
      },
    );

    test('a delete sends the paths by name', () async {
      final seen = <http.Request>[];
      await _answering({
        'success': true,
        'message': 'Documents removed successfully',
      }, seen: seen).deleteDocuments(['custom-documents/a.json']);
      expect(seen.single.method, 'DELETE');
      expect(seen.single.url.path, '/api/v1/system/remove-documents');
      expect(jsonDecode(seen.single.body), {
        'names': ['custom-documents/a.json'],
      });
    });

    test('Read in full pins the document in the workspace', () async {
      final seen = <http.Request>[];
      await _answering({
        'message': 'Pin status updated successfully',
      }, seen: seen).pinDocument('w', 'custom-documents/a.json', pinned: true);
      expect(seen.single.url.path, '/api/v1/workspace/w/update-pin');
      expect(jsonDecode(seen.single.body), {
        'docPath': 'custom-documents/a.json',
        'pinStatus': true,
      });
    });

    test('a pin on a document the workspace does not use says so', () async {
      final error = await _failure(
        _api((_) async => http.Response('Not Found', 404))
            .pinDocument('w', 'a/b.json', pinned: true),
      );
      expect(error.message, 'This workspace does not use the document.');
    });

    test('a workspace\'s documents say whether they are pinned', () async {
      final w = await _answering({
        'workspace': [
          {
            'slug': 'w',
            'documents': [
              {'docpath': 'f/a.json', 'pinned': true, 'metadata': '{}'},
              {'docpath': 'f/b.json', 'pinned': false},
            ],
          },
        ],
      }).workspace('w');
      expect(w.documents.map((d) => d.pinned), [true, false]);
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

    test('a new workspace sends its instructions as its prompt', () async {
      final seen = <http.Request>[];
      await _answering({
        'workspace': {'slug': 'r', 'name': 'Recipes'},
      }, seen: seen).createWorkspace('Recipes', prompt: 'Answer as a chef.');
      expect(jsonDecode(seen.single.body), {
        'name': 'Recipes',
        'openAiPrompt': 'Answer as a chef.',
      });
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

    test(
      'Main chat\'s history is the workspace\'s own, read newest first and put '
      'oldest first',
      () async {
        final seen = <http.Request>[];
        final turns = await _answering({
          'history': [
            {'role': 'user', 'content': 'And now?', 'chatId': 9},
            {'role': 'assistant', 'content': 'Later.', 'chatId': 9},
            {'role': 'user', 'content': 'When?', 'chatId': 4},
            {'role': 'assistant', 'content': 'Soon.', 'chatId': 4},
          ],
        }, seen: seen).history('w', null);
        expect(seen.single.method, 'GET');
        expect(seen.single.url.path, '/api/v1/workspace/w/chats');
        expect(seen.single.url.queryParameters, {
          'orderBy': 'desc',
          'limit': '${HttpAnythingLlmApi.mainChatExchanges}',
        });
        expect(turns.map((t) => (t.text, t.chatId)), [
          ('When?', 4),
          ('Soon.', 4),
          ('And now?', 9),
          ('Later.', 9),
        ]);
      },
    );

    test('a Main chat history that comes oldest first stays so', () async {
      final turns = await _answering({
        'history': [
          {'role': 'user', 'content': 'When?', 'chatId': 4},
          {'role': 'assistant', 'content': 'Soon.', 'chatId': 4},
          {'role': 'user', 'content': 'And now?', 'chatId': 9},
          {'role': 'assistant', 'content': 'Later.', 'chatId': 9},
        ],
      }).history('w', null);
      expect(turns.map((t) => t.text), [
        'When?',
        'Soon.',
        'And now?',
        'Later.',
      ]);
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

    test('a history turn keeps its exchange id', () async {
      final turns = await _answering({
        'history': [
          {'role': 'user', 'content': 'Q', 'chatId': 7},
          {'role': 'assistant', 'content': 'A', 'chatId': 7},
          {'role': 'user', 'content': 'Old'},
        ],
      }).history('w', 't');
      expect(turns.map((t) => t.chatId), [7, 7, null]);
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

    test(
      'resetChat posts reset with no message and reads the one chunk',
      () async {
        final seen = <http.BaseRequest>[];
        await streaming([
          data({
            'type': 'textResponse',
            'textResponse': 'Chat history was reset!',
            'close': true,
            'sources': [],
          }),
        ], seen: seen).resetChat('w', 't');
        expect(
          seen.single.url.path,
          '/api/v1/workspace/w/thread/t/stream-chat',
        );
        expect(jsonDecode((seen.single as http.Request).body), {'reset': true});
      },
    );

    test(
      'Main chat asks the workspace itself, with no thread or session',
      () async {
        final seen = <http.BaseRequest>[];
        await streaming([
          data({
            'type': 'textResponseChunk',
            'textResponse': 'Hi',
            'close': true,
          }),
        ], seen: seen).streamChat('w', null, 'Hello').drain<void>();
        expect(seen.single.url.path, '/api/v1/workspace/w/stream-chat');
        expect(jsonDecode((seen.single as http.Request).body), {
          'message': 'Hello',
        });
      },
    );

    test('resetChat clears Main chat on the workspace itself', () async {
      final seen = <http.BaseRequest>[];
      await streaming([
        data({
          'type': 'textResponse',
          'textResponse': 'Chat history was reset!',
          'close': true,
        }),
      ], seen: seen).resetChat('w', null);
      expect(seen.single.url.path, '/api/v1/workspace/w/stream-chat');
      expect(jsonDecode((seen.single as http.Request).body), {'reset': true});
    });

    test('a message sends a mode only when it is given one', () async {
      final seen = <http.BaseRequest>[];
      Future<void> ask(ChatMode? mode) => streaming([
        data({'type': 'textResponseChunk', 'textResponse': '', 'close': true}),
      ], seen: seen).streamChat('w', 't', 'Hi', mode: mode).drain<void>();
      await ask(null);
      await ask(ChatMode.chat);
      expect(
        [for (final r in seen) jsonDecode((r as http.Request).body)],
        [
          {'message': 'Hi'},
          {'message': 'Hi', 'mode': 'chat'},
        ],
      );
    });

    test('an answer that goes silent is given up after idle', () async {
      final silent = StreamController<List<int>>();
      addTearDown(silent.close);
      final api = HttpAnythingLlmApi(
        holder: ConnectionHolder(_connection),
        idle: const Duration(milliseconds: 50),
        client: MockClient.streaming((request, body) async {
          await body.drain<void>();
          return http.StreamedResponse(silent.stream, 200);
        }),
      );
      final error = await _failure(api.streamChat('w', 't', 'Hi').drain());
      expect(error.message, contains('sent nothing for too long'));
    });

    test('a connection dropped mid-answer is a CutOff, which the server may finish', () async {
      final api = HttpAnythingLlmApi(
        holder: ConnectionHolder(_connection),
        client: MockClient.streaming((request, body) async {
          await body.drain<void>();
          return http.StreamedResponse(
            Stream.error(http.ClientException('Connection reset')),
            200,
          );
        }),
      );
      final error = await _failure(api.streamChat('w', 't', 'Hi').drain());
      expect(error, isA<CutOff>());
      expect(error.message, 'The connection dropped: Connection reset');
    });

    // Before the answer's headers, whether the server has the question decides between waiting
    // for its answer and Not sent.
    Future<ApiException> openingFails(
      Future<http.Response> Function() answer,
    ) => _failure(
      _api(
        (_) => answer(),
        timeout: const Duration(milliseconds: 50),
      ).streamChat('w', 't', 'Hi').drain(),
    );

    test(
      'no headers within the limit is a CutOff, since the request went out',
      () async {
        final error = await openingFails(
          () => Completer<http.Response>().future,
        );
        expect(error, isA<CutOff>());
        expect(error.message, contains('may still be answering'));
      },
    );

    test('a connection closed before the headers is a CutOff', () async {
      final error = await openingFails(
        () => throw http.ClientException(
          'Connection closed before full header was received',
        ),
      );
      expect(error, isA<CutOff>());
      expect(error.message, contains('closed before the answer began'));
    });

    test('a server that cannot be reached is Not sent', () async {
      final error = await openingFails(
        () => throw const SocketException('Connection refused'),
      );
      expect(error, isA<NotSent>());
      expect(error.message, contains('Connection refused'));
    });

    test('sends no mode, so the workspace\'s own chat mode applies', () async {
      late Map<String, dynamic> body;
      await HttpAnythingLlmApi(
        holder: ConnectionHolder(_connection),
        client: MockClient.streaming((request, bytes) async {
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

    test('a tool call is named in words', () async {
      final events = await streaming([
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
      ]).streamChat('w', 't', 'Search').toList();
      expect(
        [for (final s in events.whereType<StatusChunk>()) s.text],
        ['Running web-browsing'],
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

    test('a refused request is decoded like any other, and Not sent', () async {
      final stream = streaming([
        '{"error":"Invalid API Key"}',
      ], status: 403).streamChat('w', 't', 'Hi');
      await expectLater(
        stream.toList(),
        throwsA(isA<NotSent>().having((e) => e.status, 'status', 403)),
      );
    });

    test(
      'stopping before the first chunk lets go of the answer at once',
      () async {
        final body = StreamController<List<int>>();
        final api = HttpAnythingLlmApi(
          holder: ConnectionHolder(_connection),
          client: MockClient.streaming(
            (request, _) async => http.StreamedResponse(body.stream, 200),
          ),
        );
        final subscription = api.streamChat('w', 't', 'Hi').listen(null);
        await pumpEventQueue();
        expect(body.hasListener, isTrue);
        await subscription.cancel().timeout(const Duration(seconds: 1));
        expect(body.hasListener, isFalse);
        await body.close();
      },
    );
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
        expect(w.documents.single.path, 'c/a.json');
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
        client: MockClient.streaming((request, body) async {
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
        client: MockClient.streaming((request, body) async {
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

    test('the vector count is the server\'s number', () async {
      final seen = <http.Request>[];
      expect(
        await _answering({'vectorCount': 796}, seen: seen).vectorCount(),
        796,
      );
      expect(seen.single.url.path, '/api/v1/system/vector-count');
      await _failure(_answering({'vectorCount': 'many'}).vectorCount());
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
  });

  group('several users', () {
    test('whether the server has several users is its own answer', () async {
      final seen = <http.Request>[];
      expect(
        await _answering({'isMultiUser': true}, seen: seen).multiUser(),
        isTrue,
      );
      expect(seen.single.method, 'GET');
      expect(seen.single.url.path, '/api/v1/admin/is-multi-user-mode');
      expect(await _answering({'isMultiUser': false}).multiUser(), isFalse);
      expect(await _answering({}).multiUser(), isFalse);
    });

    test('the users are each an id, a name and a role', () async {
      final seen = <http.Request>[];
      final users = await _answering({
        'users': [
          {'id': 1, 'username': 'john_doe', 'role': 'admin'},
          {'id': 2, 'username': 'jane_smith', 'role': 'default'},
          {'username': 'no id', 'role': 'default'},
        ],
      }, seen: seen).users();
      expect(seen.single.url.path, '/api/v1/users');
      expect(
        [for (final u in users) (u.id, u.name, u.role)],
        [(1, 'john_doe', 'admin'), (2, 'jane_smith', 'default')],
      );
    });

    test('a single-user server refuses the users', () async {
      final error = await _failure(
        _api(
          (_) async => http.Response(
            'Instance is not in Multi-User mode. Permission denied.',
            401,
          ),
        ).users(),
      );
      expect(error.status, 401);
    });

    test('a workspace\'s users are read by its id', () async {
      final seen = <http.Request>[];
      final members = await _answering({
        'users': [
          {'userId': 1, 'role': 'admin'},
          {'userId': 2, 'role': 'member'},
        ],
      }, seen: seen).workspaceUsers(79);
      expect(seen.single.url.path, '/api/v1/admin/workspaces/79/users');
      expect([for (final m in members) m.id], [1, 2]);
    });

    test('each workspace carries its id', () async {
      final list = await _answering({
        'workspaces': [
          {'id': 79, 'slug': 'q3', 'name': 'Q3'},
          {'slug': 'bare', 'name': 'Bare'},
        ],
      }).workspaces();
      expect([for (final w in list) w.id], [79, null]);
    });

    test('a new chat names the user it is saved as, when given', () async {
      final seen = <http.Request>[];
      final api = _answering({
        'thread': {'slug': 'th-1', 'name': 'New chat', 'user_id': 2},
      }, seen: seen);
      await api.createThread('w', userId: 2);
      await api.createThread('w');
      expect(
        [for (final r in seen) jsonDecode(r.body)],
        [
          {'name': 'New chat', 'userId': 2},
          {'name': 'New chat'},
        ],
      );
    });

    test('a message names the user it is saved as, when given', () async {
      final seen = <http.BaseRequest>[];
      final api = HttpAnythingLlmApi(
        holder: ConnectionHolder(_connection),
        client: MockClient.streaming((request, body) async {
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
      await api.streamChat('w', 't', 'Hi', userId: 2).drain<void>();
      await api.streamChat('w', 't', 'Hi').drain<void>();
      expect(seen.first.url.path, '/api/v1/workspace/w/thread/t/stream-chat');
      expect(
        [for (final r in seen) jsonDecode((r as http.Request).body)],
        [
          {'message': 'Hi', 'userId': 2},
          {'message': 'Hi'},
        ],
      );
    });

    test('export chats is the CSV the server sends', () async {
      final seen = <http.Request>[];
      const csv = 'id,workspace,prompt,response\n1,Q3,Hi,Hello\n';
      final bytes = await _api((request) async {
        seen.add(request);
        return http.Response(
          csv,
          200,
          headers: {'content-type': 'text/csv; charset=utf-8'},
        );
      }).exportChats();
      expect(seen.single.method, 'GET');
      expect(seen.single.url.path, '/api/v1/system/export-chats');
      expect(seen.single.url.queryParameters, {'type': 'csv'});
      expect(seen.single.headers['Authorization'], 'Bearer SECRET-KEY');
      expect(utf8.decode(bytes), csv);
      final refused = await _failure(
        _answering({'error': 'Invalid export type'}, status: 400).exportChats(),
      );
      expect(refused.message, 'Invalid export type');
    });
  });

  group('answerImage', () {
    final picture = Uri.parse(
      'https://host.example.ts.net:8080/pictures/a.png',
    );

    /// A client that answers [body] with [status], recording each request in [seen].
    HttpAnythingLlmApi images(
      Stream<List<int>> body, {
      int status = 200,
      List<http.BaseRequest>? seen,
      Duration timeout = const Duration(seconds: 15),
    }) => HttpAnythingLlmApi(
      holder: ConnectionHolder(_connection),
      timeout: timeout,
      client: MockClient.streaming((request, _) async {
        seen?.add(request);
        return http.StreamedResponse(
          body,
          status,
          headers: {'content-type': 'image/png'},
        );
      }),
    );

    test('reads the image whole, with no key, password or token', () async {
      final seen = <http.BaseRequest>[];
      final api = images(
        Stream.fromIterable([ascii.encode('o'), ascii.encode('ne')]),
        seen: seen,
      );
      expect(ascii.decode(await api.answerImage(picture)), 'one');
      expect(seen.single.url, picture);
      expect(seen.single.method, 'GET');
      expect(
        seen.single.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(seen.single.headers.values.join(), isNot(contains('SECRET-KEY')));
      // A redirect could lead off the server's host.
      expect(seen.single.followRedirects, isFalse);
    });

    test('refuses plain http', () async {
      final seen = <http.BaseRequest>[];
      final api = images(const Stream.empty(), seen: seen);
      final error = await _failure(
        api.answerImage(Uri.parse('http://host.example.com:8080/a.png')),
      );
      expect(error.message, plainHttpRefused);
      expect(seen, isEmpty);
    });

    test(
      'refuses an address off the server\'s host, sending nothing',
      () async {
        final seen = <http.BaseRequest>[];
        final api = images(const Stream.empty(), seen: seen);
        final error = await _failure(
          api.answerImage(Uri.parse('https://evil.example/a.png')),
        );
        expect(error.message, offServerImage);
        expect(seen, isEmpty);
      },
    );

    test('a missing image fails in plain words', () async {
      final api = images(
        Stream.value(ascii.encode('No such picture.')),
        status: 404,
      );
      final error = await _failure(api.answerImage(picture));
      expect(
        error.message,
        'The image could not be read: the server answered 404.',
      );
    });

    test('a body that stalls after the headers times out', () async {
      final stalled = StreamController<List<int>>()..add(ascii.encode('on'));
      addTearDown(stalled.close);
      final api = images(
        stalled.stream,
        timeout: const Duration(milliseconds: 50),
      );
      final error = await _failure(api.answerImage(picture));
      expect(error.message, contains('did not answer within'));
    });

    test('an image past the limit is refused', () async {
      final api = images(Stream.value(Uint8List(maxImageBytes + 1)));
      final error = await _failure(api.answerImage(picture));
      expect(error.message, 'The image is too large to show.');
    });
  });
}

/// AnythingLLM's web-UI login: `request-token` takes `PASS-WORD` and hands out `TOKEN-1`,
/// `TOKEN-2` and so on, and each route in [routes] answers its body to the token in [valid]
/// alone, and 401 to anything else. Every request goes into [seen].
