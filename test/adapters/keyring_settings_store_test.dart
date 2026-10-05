import 'package:everything/adapters/keyring_settings_store.dart';
import 'package:everything/core/connection.dart';
import 'package:everything/core/ports.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _connection = Connection(
  baseUrl: 'https://host.example.ts.net:3001',
  apiKey: 'SECRET-KEY',
);

void main() {
  test('nothing saved loads as null', () async {
    FlutterSecureStorage.setMockInitialValues({});
    expect(await KeyringSettingsStore().load(), isNull);
  });

  test('a saved connection loads back', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = KeyringSettingsStore();
    await store.save(_connection);
    expect(await store.load(), _connection);
  });

  test('clear removes it', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = KeyringSettingsStore();
    await store.save(_connection);
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('an unreadable entry says to enter it again', () async {
    FlutterSecureStorage.setMockInitialValues({
      'anythingllm-connection': 'not json',
    });
    await expectLater(
      KeyringSettingsStore().load(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('Enter it again'),
        ),
      ),
    );
  });

  test('an entry missing a field is unreadable too', () async {
    FlutterSecureStorage.setMockInitialValues({
      'anythingllm-connection': '{"baseUrl":"https://h"}',
    });
    await expectLater(
      KeyringSettingsStore().load(),
      throwsA(isA<ApiException>()),
    );
  });
}
