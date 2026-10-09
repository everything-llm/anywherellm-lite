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
);

HttpAnythingLlmApi _api(
  Future<http.Response> Function(http.Request) handler, {
  bool allowHttp = true,
  Connection? current = _connection,
}) => HttpAnythingLlmApi(
  holder: ConnectionHolder(current),
  client: MockClient(handler),
  allowHttp: allowHttp,
  timeout: const Duration(seconds: 5),
);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

const _list = {
  'workspace': 'q3',
  'used': 32379,
  'warn': 4294967296,
  'limit': 5368709120,
  'truncated': false,
  'files': [
    {
      'id': 'threads/23/career/notes.md',
      'name': 'notes.md',
      'dir': 'career',
      'size': 2664,
      'modified': 1791908153,
      'area': 'work',
      'thread': '23',
      'expires': 1792512953,
    },
  ],
};

Future<ApiException> _failure(Future<void> call) async {
  try {
    await call;
  } on ApiException catch (error) {
    return error;
  }
  fail('expected an ApiException');
}

void main() {
  group('the created files', () {
    test(
      'are listed from the host\'s cards port with the developer key',
      () async {
        final seen = <http.Request>[];
        final api = _api((request) async {
          seen.add(request);
          return _json(_list);
        });
        final list = (await api.createdFiles('q3'))!;
        expect(list.files.single.name, 'notes.md');
        expect(list.used, 32379);
        expect(
          seen.single.url.toString(),
          'https://host.example.ts.net:8445/_live/sandbox/files/q3',
        );
        expect(seen.single.headers['Authorization'], 'Bearer SECRET-KEY');
      },
    );

    test(
      'are an empty list for a workspace the host has no sandbox for',
      () async {
        final api = _api(
          (_) async => _json({'error': 'no sandbox for this workspace'}, 404),
        );
        final list = await api.createdFiles('new');
        expect(list!.files, isEmpty);
      },
    );

    test('are not listed again by a server that has no such route', () async {
      var asked = 0;
      final api = _api((_) async {
        asked++;
        return http.Response('<html>No such app.</html>', 404);
      });
      expect(await api.createdFiles('q3'), isNull);
      expect(await api.createdFiles('q3'), isNull);
      expect(asked, 1);
      await api.relayFound(again: true);
      await api.createdFiles('q3');
      expect(asked, greaterThan(1));
    });

    test(
      'fail in plain words when the key is refused or the answer is not a list',
      () async {
        final refused = _api(
          (_) async => _json({'error': 'No valid api key found.'}, 403),
        );
        expect(
          (await _failure(refused.createdFiles('q3'))).message,
          'The server rejected the key.',
        );
        final odd = _api((_) async => _json({'files': 'none'}));
        expect(
          (await _failure(odd.createdFiles('q3'))).message,
          'The server did not answer like the sandbox.',
        );
      },
    );

    test(
      'fail before the key is sent over plain http where it is not allowed',
      () async {
        final api = HttpAnythingLlmApi(
          holder: ConnectionHolder(
            const Connection(
              baseUrl: 'http://host.example.ts.net:3001',
              apiKey: 'K',
            ),
          ),
          allowHttp: false,
          client: MockClient((_) async => throw StateError('must not ask')),
        );
        expect(await _failure(api.createdFiles('q3')), isA<ApiException>());
        expect(
          await _failure(api.downloadCreated('q3', 'project/a')),
          isA<ApiException>(),
        );
        expect(
          await _failure(api.keepCreated('q3', 'threads/1/a')),
          isA<ApiException>(),
        );
        expect(
          await _failure(api.deleteCreated('q3', 'project/a')),
          isA<ApiException>(),
        );
      },
    );

    test('are downloaded by their id, as the bytes', () async {
      final seen = <http.Request>[];
      final api = _api((request) async {
        seen.add(request);
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {
            'content-type': 'application/octet-stream',
            'content-disposition': "attachment; filename*=UTF-8''a.bin",
          },
        );
      });
      expect(await api.downloadCreated('q3', 'project/a b.bin'), [1, 2, 3]);
      expect(seen.single.url.path, '/_live/sandbox/files/q3/download');
      expect(seen.single.url.queryParameters, {'path': 'project/a b.bin'});
      final gone = _api((_) async => _json({'error': "there's no 'x'"}, 404));
      expect(
        (await _failure(gone.downloadCreated('q3', 'x'))).message,
        "there's no 'x'",
      );
      final big = _api(
        (_) async => _json({'error': 'too big to send here'}, 413),
      );
      expect(
        (await _failure(big.downloadCreated('q3', 'x'))).message,
        'too big to send here',
      );
    });

    test('are kept with a POST, and answer where they are now', () async {
      final seen = <http.Request>[];
      final api = _api((request) async {
        seen.add(request);
        return _json({'id': 'project/career/notes.md', 'kept': true});
      });
      expect(
        await api.keepCreated('q3', 'threads/23/career/notes.md'),
        'project/career/notes.md',
      );
      expect(seen.single.method, 'POST');
      expect(seen.single.url.path, '/_live/sandbox/files/q3/keep');
      expect(seen.single.url.queryParameters, {
        'path': 'threads/23/career/notes.md',
      });
      final busy = _api(
        (_) async =>
            _json({'error': 'code is still running in this workspace'}, 409),
      );
      final failure = await _failure(busy.keepCreated('q3', 'threads/23/a'));
      expect(failure.message, 'code is still running in this workspace');
      expect(failure.status, 409);
      final odd = _api((_) async => _json({'kept': true}));
      expect(await _failure(odd.keepCreated('q3', 'x')), isA<ApiException>());
    });

    test('are deleted with a POST', () async {
      final seen = <http.Request>[];
      final api = _api((request) async {
        seen.add(request);
        return _json({'id': 'project/a', 'deleted': true});
      });
      await api.deleteCreated('q3', 'project/a');
      expect(seen.single.method, 'POST');
      expect(seen.single.url.path, '/_live/sandbox/files/q3/delete');
      final gone = _api((_) async => _json({'error': "there's no 'x'"}, 404));
      expect(
        (await _failure(gone.deleteCreated('q3', 'x'))).message,
        "there's no 'x'",
      );
    });

    test('never put the key in a failure', () async {
      final api = _api((_) async => _json({'error': 'nope'}, 409));
      for (final call in [
        api.keepCreated('q3', 'x'),
        api.deleteCreated('q3', 'x'),
        api.downloadCreated('q3', 'x'),
      ]) {
        expect((await _failure(call)).message, isNot(contains('SECRET-KEY')));
      }
    });
  });
}
