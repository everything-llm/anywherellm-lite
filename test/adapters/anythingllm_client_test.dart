import 'dart:async';
import 'dart:io';

import 'package:everything/adapters/anythingllm_client.dart';
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
}) => HttpAnythingLlmApi(client: MockClient(handler), timeout: timeout);

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
}
