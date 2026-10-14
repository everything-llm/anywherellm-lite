import 'dart:convert';
import 'dart:io';

import 'package:anywherellm/adapters/companion_client.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _connection = Connection(
  baseUrl: 'https://host.example.ts.net:3001',
  apiKey: 'SECRET-KEY',
);

/// The toolkit as a companion, answering through [handler].
CompanionClient _api(
  Future<http.Response> Function(http.Request) handler, {
  ConnectionHolder? holder,
}) => CompanionClient(
  toolkitCompanion,
  holder: holder ?? ConnectionHolder(_connection),
  client: MockClient(handler),
  timeout: const Duration(seconds: 5),
  healthTimeout: const Duration(seconds: 5),
);

/// A client that answers [body] to every request and records each one in [seen].
CompanionClient _answering(
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
  group('features', () {
    test('asks /health on 8467 without the key, and believes only the toolkit '
        'server', () async {
      final seen = <http.Request>[];
      final api = _answering({
        'service': 'anythingllm-toolkit',
        'server': 'toolkit',
        'ok': true,
      }, seen: seen);
      expect(await api.features(), isEmpty);
      expect(
        seen.single.url.toString(),
        'https://host.example.ts.net:8467/health',
      );
      expect(seen.single.headers.containsKey('Authorization'), isFalse);
    });

    test('are null for anything else that answers, or nothing', () async {
      expect(await _answering({'service': 'other'}).features(), isNull);
      expect(
        await _api((_) async => http.Response('<html>AnythingLLM</html>', 200))
            .features(),
        isNull,
      );
      expect(
        await _answering({
          'service': 'anythingllm-toolkit',
        }, status: 502).features(),
        isNull,
      );
      expect(
        await _api((_) async => throw const SocketException('refused'))
            .features(),
        isNull,
      );
    });

    test('are remembered per connection, until asked again', () async {
      var asked = 0;
      final holder = ConnectionHolder(_connection);
      final api = _api((request) async {
        asked++;
        return http.Response('{"service":"anythingllm-toolkit"}', 200);
      }, holder: holder);
      await api.features();
      await api.features();
      expect(asked, 1);
      await api.features(again: true);
      expect(asked, 2);
      holder.current = const Connection(
        baseUrl: 'https://other.example:3001',
        apiKey: 'K',
      );
      await api.features();
      expect(asked, 3);
    });

    test(
      'are null with no server, or at a public http address, without asking',
      () async {
        var asked = 0;
        Future<http.Response> count(http.Request _) async {
          asked++;
          return http.Response('{"service":"anythingllm-toolkit"}', 200);
        }

        expect(
          await _api(count, holder: ConnectionHolder()).features(),
          isNull,
        );
        expect(
          await _api(
            count,
            holder: ConnectionHolder(_connection)
              ..companions = {
                toolkitCompanion.service: Uri.parse(
                  'http://toolkit.example.com',
                ),
              },
          ).features(),
          isNull,
        );
        expect(asked, 0);
      },
    );
  });

  test('are asked at the address said, under its path', () async {
    final seen = <Uri>[];
    final api = _api(
      (request) async {
        seen.add(request.url);
        return http.Response('{"service":"anythingllm-toolkit"}', 200);
      },
      holder: ConnectionHolder(_connection)
        ..companions = {
          toolkitCompanion.service: Uri.parse('http://toolkit.lan/v2'),
        },
    );
    expect(await api.features(), isEmpty);
    expect(seen.single.toString(), 'http://toolkit.lan/v2/health');
  });

  group('calls', () {
    test(
      'send the key, and a refused one says so in the companion\'s name',
      () async {
        final seen = <http.Request>[];
        final api = _api((request) async {
          seen.add(request);
          return http.Response(jsonEncode({'error': 'bad key'}), 401);
        });
        final error = await _failure(api.json('GET', ['memory-switches']));
        expect(seen.single.headers['Authorization'], 'Bearer SECRET-KEY');
        expect(error.message, 'The toolkit did not accept the key.');
        expect(error.message, isNot(contains('SECRET-KEY')));
      },
    );

    test('a bare 404 is a route the companion lacks', () async {
      final api = _api((_) async => http.Response('Not Found', 404));
      expect(
        await _failure(api.json('GET', ['workspaces', 'home', 'memories'])),
        isA<NoRoute>(),
      );
    });

    test('a server out of reach is named, without the key', () async {
      final api = _api((_) async => throw const SocketException('refused'));
      final error = await _failure(api.json('GET', ['memory-switches']));
      expect(error.message, contains('the toolkit on host.example.ts.net'));
      expect(error.message, isNot(contains('SECRET-KEY')));
    });
  });
}
