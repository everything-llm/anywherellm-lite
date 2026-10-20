import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/toolkit.dart';
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
        normalizeBaseUrl('  http://100.101.2.3:3001/  '),
        'http://100.101.2.3:3001',
      );
      expect(normalizeBaseUrl('http://h:3001/api'), 'http://h:3001');
      expect(normalizeBaseUrl('http://h:3001/api/'), 'http://h:3001');
    });

    test('keeps a path prefix behind a proxy', () {
      expect(normalizeBaseUrl('https://h/llm/'), 'https://h/llm');
      expect(normalizeBaseUrl('https://h/llm/api'), 'https://h/llm');
    });

    test('plain http only on a private network', () {
      for (final home in [
        'http://localhost:3001',
        'http://nas:3001',
        'http://box.local',
        'http://owen.tail30d4c5.ts.net:3001',
        'http://owen.tail30d4c5.ts.net.:3001',
        'http://192.168.1.20:3001',
        'http://10.0.2.2:3001',
        'http://172.20.0.5',
        'http://100.101.2.3',
        'http://[::1]:3001',
        'http://[fd12::3]',
      ]) {
        expect(normalizeBaseUrl(home), isNotEmpty, reason: home);
      }
      for (final public in [
        'http://ai.example.com',
        'http://8.8.8.8',
        'http://100.1.2.3',
        'http://172.32.0.1',
        'http://[2001:db8::1]',
      ]) {
        expect(
          () => normalizeBaseUrl(public),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              plainHttpRefused,
            ),
          ),
          reason: public,
        );
      }
    });

    test('a public host that looks private is refused', () {
      for (final public in [
        '127.evil.example',
        '10.0.0.1.nip.io',
        '134744072',
        '0x7f000001',
        '010.0.0.1',
        '0x0a.0.0.1',
        '10.1',
        '127.1',
        '+10.0.0.1',
        '10.0.0.256',
      ]) {
        expect(isPrivateHost(public), isFalse, reason: public);
      }
      for (final home in [
        '127.0.0.1',
        '0.0.0.0',
        '10.0.0.1',
        '100.64.0.1',
        'nas',
        'nas.local',
        'fd00::1',
      ]) {
        expect(isPrivateHost(home), isTrue, reason: home);
      }
      expect(isLoopback('127.evil.example'), isFalse);
      expect(isLoopback('127.0.0.1'), isTrue);
      expect(
        () => normalizeBaseUrl('http://127.evil.example:3001'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            plainHttpRefused,
          ),
        ),
      );
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

    test('a name outside ASCII is refused, and its xn-- form taken', () {
      // The first letter is Cyrillic, which Uri.parse percent-escapes.
      expect(
        () => normalizeBaseUrl('https://\u0430nything.example:3001'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('xn--'),
          ),
        ),
      );
      expect(
        normalizeBaseUrl('https://xn--nything-3fg.example:3001'),
        'https://xn--nything-3fg.example:3001',
      );
      expect(
        () => normalizeBaseUrl("http://nas'(x):3001"),
        throwsA(isA<ApiException>()),
        reason:
            'only letters, digits, dots, hyphens and underscores name a host',
      );
      expect(
        normalizeBaseUrl('http://[fe80::1]:3001'),
        'http://[fe80::1]:3001',
      );
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

    test('a key with a character outside printable ASCII is refused', () {
      for (final key in ['AB\u200bCD', 'AB\u00a0CD', 'AB\nCD', 'AB CD', 'ÅB']) {
        expect(
          () => Connection.parse('https://h:3001', key),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              allOf(contains('a key cannot'), isNot(contains('CD'))),
            ),
          ),
          reason: key,
        );
      }
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

  group('pairing code', () {
    test('carries the address and key there and back', () {
      const connection = Connection(
        baseUrl: 'https://h.example.ts.net:3001/llm',
        apiKey: 'AB&C=D+E/F?G#H',
      );
      final code = _code(connection);
      expect(code, startsWith('anywherellm://connect?'));
      expect(code, isNot(contains('&C=D')));
      expect(parsePairingCode(code).connection, connection);
    });

    test('carries companions\' addresses when it names them', () {
      final pairing = parsePairingCode(
        'anywherellm://connect?url=https%3A%2F%2Fai.example.com&key=K'
        '&toolkit=https%3A%2F%2Ftoolkit.example.com%2F',
      );
      expect(pairing.connection.baseUrl, 'https://ai.example.com');
      expect(pairing.companions, {
        'toolkit': Uri.parse('https://toolkit.example.com'),
      });
      expect(
        () => parsePairingCode(
          'anywherellm://connect?url=https%3A%2F%2Fai.example.com&key=K'
          '&toolkit=http%3A%2F%2Ftoolkit.example.com',
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('an apps server\'s address, from an older code, is left out', () {
      final pairing = parsePairingCode(
        'anywherellm://connect?url=https%3A%2F%2Fai.example.com&key=K'
        '&apps=http%3A%2F%2Fapps.lan',
      );
      expect(pairing.connection.baseUrl, 'https://ai.example.com');
      expect(pairing.companions, isEmpty);
    });

    test('anything else is refused', () {
      for (final bad in [
        'https://h.example.ts.net:3001',
        'just words',
        'anywherellm://connect?url=https%3A%2F%2Fh',
        'anywherellm://other?url=https%3A%2F%2Fh&key=k',
      ]) {
        expect(
          () => parsePairingCode(bad),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              contains('not an AnywhereLLM pairing code'),
            ),
          ),
          reason: bad,
        );
      }
    });

    test('an address it carries is checked as a typed one', () {
      final code = _code(const Connection(baseUrl: 'ftp://h', apiKey: 'k'));
      expect(() => parsePairingCode(code), throwsA(isA<ApiException>()));
    });
  });

  test(
    'a companion runs where its code says, and nowhere a code did not say',
    () {
      final holder =
          ConnectionHolder(
              const Connection(baseUrl: 'https://ai.example.com', apiKey: 'K'),
            )
            ..companions = {
              toolkitCompanion.code: Uri.parse('https://bridge.example.com'),
            };
      expect(
        holder.addressOf(toolkitCompanion),
        Uri.parse('https://bridge.example.com'),
      );
      holder.companions = const {};
      expect(
        holder.addressOf(toolkitCompanion),
        isNull,
        reason: 'the key never goes to a guessed address',
      );
    },
  );
}

/// The pairing code that carries [connection], as AnywhereLLM on a computer drew it.
String _code(Connection connection) => Uri(
  scheme: 'anywherellm',
  host: 'connect',
  queryParameters: {'url': connection.baseUrl, 'key': connection.apiKey},
).toString();
