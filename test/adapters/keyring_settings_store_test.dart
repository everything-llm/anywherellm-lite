import 'package:anywherellm/adapters/keyring_settings_store.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/ports.dart';
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

  test('an entry saved with a password is written again without it', () async {
    FlutterSecureStorage.setMockInitialValues({
      'anythingllm-connection':
          '{"baseUrl":"https://h:3001","apiKey":"K","password":"PASS"}',
    });
    final loaded = await KeyringSettingsStore().load();
    expect(loaded, const Connection(baseUrl: 'https://h:3001', apiKey: 'K'));
    final stored = await const FlutterSecureStorage().read(
      key: 'anythingllm-connection',
    );
    expect(stored, isNot(contains('PASS')));
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
