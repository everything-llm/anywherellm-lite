import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeBaseUrl', () {
    test('keeps a clean address', () {
      expect(
        normalizeBaseUrl('https://host.example.ts.net:3001'),
        'https://host.example.ts.net:3001',
      );
    });

    test('trims, and drops trailing slashes and /api', () {
      expect(
        normalizeBaseUrl('  http://100.1.2.3:3001/  '),
        'http://100.1.2.3:3001',
      );
      expect(normalizeBaseUrl('http://h:3001/api'), 'http://h:3001');
      expect(normalizeBaseUrl('http://h:3001/api/'), 'http://h:3001');
    });

    test('keeps a path prefix behind a proxy', () {
      expect(normalizeBaseUrl('https://h/llm/'), 'https://h/llm');
      expect(normalizeBaseUrl('https://h/llm/api'), 'https://h/llm');
    });

    test('empty is refused', () {
      expect(() => normalizeBaseUrl('  '), throwsA(isA<ApiException>()));
    });

    test('no scheme, a wrong scheme or no host is refused', () {
      for (final bad in ['host:3001', 'ftp://h', 'https://', 'just words']) {
        expect(
          () => normalizeBaseUrl(bad),
          throwsA(isA<ApiException>()),
          reason: bad,
        );
      }
    });

    test('a query, fragment or login is refused', () {
      for (final bad in ['https://h/?a=1', 'https://h/#x', 'https://u:p@h']) {
        expect(
          () => normalizeBaseUrl(bad),
          throwsA(isA<ApiException>()),
          reason: bad,
        );
      }
    });
  });

  group('Connection.parse', () {
    test('cleans the address and trims the key', () {
      final connection = Connection.parse(' https://h:3001/api/ ', '  K1 ');
      expect(connection.baseUrl, 'https://h:3001');
      expect(connection.apiKey, 'K1');
      expect(connection.host, 'h');
    });

    test('an empty key is refused', () {
      expect(
        () => Connection.parse('https://h:3001', '  '),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Enter the API key.',
          ),
        ),
      );
    });

    test('a bad address is refused', () {
      expect(
        () => Connection.parse('nonsense', 'K1'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  test('a connection never prints its key', () {
    const connection = Connection(baseUrl: 'https://h', apiKey: 'SECRET');
    expect('$connection', isNot(contains('SECRET')));
  });
}
