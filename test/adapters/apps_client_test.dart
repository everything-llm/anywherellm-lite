import 'dart:convert';
import 'dart:io';

import 'package:anywherellm/adapters/apps_client.dart';
import 'package:anywherellm/core/apps.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _connection = Connection(
  baseUrl: 'https://host.example.ts.net:3001',
  apiKey: 'SECRET-KEY',
  password: 'PASS',
);

const _app = AppRef('home', 'groceries');

HttpAppsApi _api(
  Future<http.Response> Function(http.Request) handler, {
  ConnectionHolder? holder,
}) => HttpAppsApi(
  holder: holder ?? ConnectionHolder(_connection),
  client: MockClient(handler),
);

/// A client that answers [body] to every request and records each one in [seen].
HttpAppsApi _answering(
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
  group('available', () {
    test('asks /health on 8466 without the key, and believes only the apps '
        'server', () async {
      final seen = <http.Request>[];
      final api = _answering({
        'service': 'anythingllm-apps-v2',
        'server': 'cards',
        'ok': true,
      }, seen: seen);
      expect(await api.available(), isTrue);
      expect(
        seen.single.url.toString(),
        'https://host.example.ts.net:8466/health',
      );
      expect(seen.single.headers.containsKey('Authorization'), isFalse);
    });

    test('is false for anything else that answers, or nothing', () async {
      expect(await _answering({'service': 'other'}).available(), isFalse);
      expect(
        await _api((_) async => http.Response('<html>AnythingLLM</html>', 200))
            .available(),
        isFalse,
      );
      expect(
        await _answering({
          'service': 'anythingllm-apps-v2',
        }, status: 502).available(),
        isFalse,
      );
      expect(
        await _api((_) async => throw const SocketException('refused'))
            .available(),
        isFalse,
      );
    });

    test('is remembered per connection, until asked again', () async {
      var asked = 0;
      final holder = ConnectionHolder(_connection);
      final api = _api((request) async {
        asked++;
        return http.Response('{"service":"anythingllm-apps-v2"}', 200);
      }, holder: holder);
      await api.available();
      await api.available();
      expect(asked, 1);
      await api.available(again: true);
      expect(asked, 2);
      holder.current = const Connection(
        baseUrl: 'https://other.example:3001',
        apiKey: 'K',
      );
      await api.available();
      expect(asked, 3);
    });

    test('is false with no server, or an http one, without asking', () async {
      var asked = 0;
      Future<http.Response> count(http.Request _) async {
        asked++;
        return http.Response('{"service":"anythingllm-apps-v2"}', 200);
      }

      expect(
        await _api(count, holder: ConnectionHolder()).available(),
        isFalse,
      );
      expect(
        await _api(
          count,
          holder: ConnectionHolder(
            const Connection(baseUrl: 'http://h:3001', apiKey: 'K'),
          ),
        ).available(),
        isFalse,
      );
      expect(asked, 0);
    });
  });

  test('the app list goes to /apps/<workspace> with the bearer key', () async {
    final seen = <http.Request>[];
    final apps = await _answering({
      'apps': [
        {'name': 'groceries', 'title': 'Groceries', 'kind': 'list'},
      ],
    }, seen: seen).apps('home');
    expect(apps.single.title, 'Groceries');
    expect(
      seen.single.url.toString(),
      'https://host.example.ts.net:8466/apps/home',
    );
    expect(seen.single.headers['Authorization'], 'Bearer SECRET-KEY');
  });

  test('each read goes to its route', () async {
    final seen = <String>[];
    final api = _api((request) async {
      seen.add('${request.method} ${request.url.path}?${request.url.query}');
      return switch (request.url.pathSegments.last) {
        'files' => http.Response(
          '{"files":[{"path":"app.json","size":2}]}',
          200,
        ),
        'file' => http.Response('{"n":1}\n', 200),
        'state' => http.Response('{"line":3,"data":{"a":1}}', 200),
        'history' => http.Response('{"commits":[{"commit":"abcdef12"}]}', 200),
        'diff' => http.Response('{"commit":"abcd","diff":"+x"}', 200),
        _ => http.Response('{}', 404),
      };
    });
    expect((await api.files(_app)).single.path, 'app.json');
    expect(await api.file(_app, 'log.jsonl'), '{"n":1}\n');
    expect((await api.state(_app, line: 3)).data, {'a': 1});
    await api.state(_app);
    expect((await api.history(_app)).single.short, 'abcdef1');
    expect(await api.diff(_app, 'abcd'), '+x');
    expect(seen, [
      'GET /apps/home/groceries/files?',
      'GET /apps/home/groceries/file?path=log.jsonl',
      'GET /apps/home/groceries/state?line=3',
      'GET /apps/home/groceries/state?',
      'GET /apps/home/groceries/history?',
      'GET /apps/home/groceries/diff?commit=abcd',
    ]);
  });

  test('each change posts its body to its route', () async {
    final seen = <String>[];
    final api = _api((request) async {
      seen.add('${request.method} ${request.url.path} ${request.body}');
      return switch (request.url.pathSegments.last) {
        'restore' => http.Response('{"line":{"n":8,"ev":"restore"}}', 200),
        'revert' => http.Response('{"commit":"new"}', 200),
        'rename' => http.Response('{"commit":null}', 200),
        _ => http.Response('{"deleted":true}', 200),
      };
    });
    expect(await api.restore(_app, 3), 8);
    expect(await api.revert(_app, '5f6c11f'), 'new');
    await api.rename(_app, 'Food');
    await api.delete(_app);
    expect(seen, [
      'POST /apps/home/groceries/restore {"line":3}',
      'POST /apps/home/groceries/revert {"commit":"5f6c11f"}',
      'POST /apps/home/groceries/rename {"title":"Food"}',
      'DELETE /apps/home/groceries ',
    ]);
  });

  group('a failure', () {
    test('says the server\'s words, with its status', () async {
      final error = await _failure(
        _answering({
          'error': 'that commit holds the log',
        }, status: 400).revert(_app, 'abc'),
      );
      expect(error.message, 'That commit holds the log.');
      expect(error.status, 400);
    });

    test('a refused key says so, and never holds the key', () async {
      final error = await _failure(
        _answering({
          'error': 'send a developer API key AnythingLLM accepts',
        }, status: 401).apps('home'),
      );
      expect(error.message, 'The apps server did not accept the key.');
      expect(error.status, 401);
      expect(error.message, isNot(contains('SECRET-KEY')));
    });

    test('a server out of reach says where, and never holds the key or '
        'password', () async {
      final error = await _failure(
        _api((_) async => throw const SocketException('Connection refused'))
            .apps('home'),
      );
      expect(error.message, contains('host.example.ts.net'));
      expect(error.message, isNot(contains('SECRET-KEY')));
      expect(error.message, isNot(contains('PASS')));
    });

    test('an http server is refused before the key is sent', () async {
      var asked = 0;
      final error = await _failure(
        _api(
          (_) async {
            asked++;
            return http.Response('{}', 200);
          },
          holder: ConnectionHolder(
            const Connection(baseUrl: 'http://h:3001', apiKey: 'K'),
          ),
        ).apps('home'),
      );
      expect(error.message, contains('https://'));
      expect(asked, 0);
    });
  });

  test('a card is read bare, without the key', () async {
    final seen = <http.Request>[];
    final api = _api((request) async {
      seen.add(request);
      return http.Response.bytes([1, 2, 3], 200);
    });
    final url = Uri.parse(
      'https://host.example.ts.net:8466/cards/home/groceries.png?once=1',
    );
    expect(await api.card(url), [1, 2, 3]);
    expect(seen.single.url, url);
    expect(seen.single.headers.containsKey('Authorization'), isFalse);
  });
}
