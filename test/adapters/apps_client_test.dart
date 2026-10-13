import 'dart:convert';
import 'dart:io';

import 'package:anywherellm/adapters/apps_client.dart';
import 'package:anywherellm/core/apps.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _connection = Connection(
  baseUrl: 'https://host.example.ts.net:3001',
  apiKey: 'SECRET-KEY',
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
        'diff' => http.Response(
          '{"commit":"abcd","diff":"+x","files":[{"path":"app.json",'
          '"status":"added","patch":"@@ -0,0 +1 @@\\n+x\\n"}]}',
          200,
        ),
        _ => http.Response('{}', 404),
      };
    });
    expect((await api.files(_app)).single.path, 'app.json');
    expect(await api.file(_app, 'log.jsonl'), '{"n":1}\n');
    expect((await api.state(_app, line: 3)).data, {'a': 1});
    await api.state(_app);
    expect((await api.history(_app)).single.short, 'abcdef1');
    final diff = await api.diff(_app, 'abcd');
    expect(diff.diff, '+x');
    expect(diff.files!.single.path, 'app.json');
    expect(diff.files!.single.status, FileChange.added);
    expect(diff.files!.single.patch, '@@ -0,0 +1 @@\n+x\n');
    expect(seen, [
      'GET /apps/home/groceries/files?',
      'GET /apps/home/groceries/file?path=log.jsonl',
      'GET /apps/home/groceries/state?line=3',
      'GET /apps/home/groceries/state?',
      'GET /apps/home/groceries/history?',
      'GET /apps/home/groceries/diff?commit=abcd',
    ]);
  });

  test(
    'push reads the key, subscribes and unsubscribes with the key',
    () async {
      final seen = <http.Request>[];
      final api = _api((request) async {
        seen.add(request);
        return switch (request.url.path) {
          '/push/key' => http.Response('{"key":"BApps"}', 200),
          '/push/subscribe' => http.Response('{"subscribed":true}', 200),
          _ => http.Response('{"unsubscribed":true}', 200),
        };
      });
      expect(await api.pushKey(), 'BApps');
      await api.subscribePush(
        const PushSubscription(
          'https://ntfy.sh/up1?up=1',
          p256dh: 'BK',
          auth: 'A',
        ),
      );
      await api.unsubscribePush('https://ntfy.sh/up1?up=1');
      expect(seen.map((r) => '${r.method} ${r.url}'), [
        'GET https://host.example.ts.net:8466/push/key',
        'POST https://host.example.ts.net:8466/push/subscribe',
        'POST https://host.example.ts.net:8466/push/unsubscribe',
      ]);
      expect(
        seen.every((r) => r.headers['Authorization'] == 'Bearer SECRET-KEY'),
        isTrue,
      );
      expect(jsonDecode(seen[1].body), {
        'endpoint': 'https://ntfy.sh/up1?up=1',
        'keys': {'p256dh': 'BK', 'auth': 'A'},
      });
      expect(jsonDecode(seen[2].body), {
        'endpoint': 'https://ntfy.sh/up1?up=1',
      });
    },
  );

  test('its features are what its health names', () async {
    final api = _answering({
      'service': 'anythingllm-apps-v2',
      'ok': true,
      'features': ['system-files', 'push', 7],
    });
    expect(await api.features(), {AppsFeature.systemFiles, AppsFeature.push});
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

    test('a server out of reach says where, and never holds the key', () async {
      final error = await _failure(
        _api((_) async => throw const SocketException('Connection refused'))
            .apps('home'),
      );
      expect(error.message, contains('host.example.ts.net'));
      expect(error.message, isNot(contains('SECRET-KEY')));
    });

    test('a public http address is refused before the key is sent', () async {
      var asked = 0;
      final error = await _failure(
        _api(
          (_) async {
            asked++;
            return http.Response('{}', 200);
          },
          holder: ConnectionHolder(_connection)
            ..companions = {
              appsCompanion.service: Uri.parse('http://apps.example.com'),
            },
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
    final card = await api.card(url);
    expect(card.bytes, [1, 2, 3]);
    expect(card.etag, isNull);
    expect(seen.single.url, url);
    expect(seen.single.headers.containsKey('Authorization'), isFalse);
    expect(seen.single.headers.containsKey('If-None-Match'), isFalse);
  });

  test('a card read again sends its ETag, and keeps its picture when the '
      'server answers 304', () async {
    final seen = <http.Request>[];
    var version = '7-5f6c11f0a2b4';
    final api = _api((request) async {
      seen.add(request);
      final tag = '"$version-dark"';
      if (request.headers['If-None-Match'] == tag) {
        return http.Response('', 304, headers: {'etag': tag});
      }
      return http.Response.bytes([version.length], 200, headers: {'etag': tag});
    });
    final url = Uri.parse(
      'https://host.example.ts.net:8466/cards/home/groceries.png?once=1',
    );
    final first = await api.card(url);
    expect(first.etag, '"7-5f6c11f0a2b4-dark"');
    final again = await api.card(url, last: first);
    expect(seen[1].headers['If-None-Match'], '"7-5f6c11f0a2b4-dark"');
    expect(identical(again, first), isTrue);

    version = '8-0a1b2c3d4e5f';
    final changed = await api.card(url, last: first);
    expect(changed.etag, '"8-0a1b2c3d4e5f-dark"');
    expect(changed.bytes, [14]);
  });

  group('one app', () {
    test('is read from /apps/<workspace>/<name>', () async {
      final seen = <http.Request>[];
      final app = await _answering({
        'name': 'groceries',
        'title': 'Groceries',
        'line': 7,
        'restorable_from': 1,
        'version': '7-5f6c11f0a2b4',
      }, seen: seen).app(_app);
      expect(app!.version, '7-5f6c11f0a2b4');
      expect(app.restorableFrom, 1);
      expect(seen.single.url.path, '/apps/home/groceries');
      expect(seen.single.headers['Authorization'], 'Bearer SECRET-KEY');
    });

    test('that the server does not know fails with its words', () async {
      final error = await _failure(
        _answering({'error': 'no such app'}, status: 404).app(_app),
      );
      expect(error.status, 404);
      expect(error.message, 'No such app.');
    });

    test('is null from an older server, which is not asked again until '
        'the server is', () async {
      for (final status in [404, 405]) {
        var asked = 0;
        final api = _api((request) async {
          if (request.url.path == '/health') {
            return http.Response('{"service":"anythingllm-apps-v2"}', 200);
          }
          asked++;
          return http.Response('{"detail":"Not Found"}', status);
        });
        expect(await api.app(_app), isNull, reason: '$status');
        expect(await api.app(_app), isNull, reason: '$status');
        expect(asked, 1, reason: '$status');
        await api.features(again: true);
        expect(await api.app(_app), isNull, reason: '$status');
        expect(asked, 2, reason: '$status');
      }
    });
  });

  group('the log', () {
    test('is read a page at a time, newest first', () async {
      final seen = <http.Request>[];
      final page = await _answering({
        'lines': [
          {'n': 6, 'ev': 'add'},
          {'n': 7, 'ev': 'tick'},
        ],
        'first': 1,
        'last': 7,
        'more': true,
      }, seen: seen).log(_app, before: 8, limit: 2);
      expect([for (final line in page!.lines) line.n], [7, 6]);
      expect(page.first, 1);
      expect(page.last, 7);
      expect(page.more, isTrue);
      expect(seen.single.url.path, '/apps/home/groceries/log');
      expect(seen.single.url.queryParameters, {'before': '8', 'limit': '2'});
    });

    test('is null from an older server', () async {
      final api = _api(
        (_) async => http.Response('{"detail":"Not Found"}', 404),
      );
      expect(await api.log(_app), isNull);
    });

    test('of an app the server does not know fails with its words', () async {
      final error = await _failure(
        _answering({'error': 'no such app'}, status: 404).log(_app),
      );
      expect(error.status, 404);
    });
  });
}
