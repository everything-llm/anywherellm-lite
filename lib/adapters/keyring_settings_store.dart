import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/connection.dart';
import '../core/ports.dart';

/// [SettingsStore] in the Android Keystore, as one entry holding the address and the key. An
/// entry an older version saved with the server's password, or with where other servers beside
/// AnythingLLM ran, is written again with the address and the key alone.
class KeyringSettingsStore implements SettingsStore {
  static const _entry = 'anythingllm-connection';

  static const _storage = FlutterSecureStorage();

  @override
  Future<Connection?> load() async {
    final stored = await _guard('read', () => _storage.read(key: _entry));
    if (stored == null) return null;
    final Connection connection;
    final bool outdated;
    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      connection = Connection(
        baseUrl: json['baseUrl'] as String,
        apiKey: json['apiKey'] as String,
      );
      outdated = json.keys.any((key) => key != 'baseUrl' && key != 'apiKey');
    } on Object {
      throw const ApiException(
        'The saved connection in the keyring is unreadable. Enter it again and save.',
      );
    }
    if (outdated) {
      try {
        await save(connection);
      } on ApiException {
        // The entry is written again on the next save; the connection works meanwhile.
      }
    }
    return connection;
  }

  @override
  Future<void> save(Connection saved) => _guard(
    'written',
    () => _storage.write(
      key: _entry,
      value: jsonEncode({'baseUrl': saved.baseUrl, 'apiKey': saved.apiKey}),
    ),
  );

  @override
  Future<void> clear() => _guard('written', () => _storage.delete(key: _entry));

  /// Runs [op], and turns any failure into an [ApiException] that says what [what] could not be
  /// done. The exception's own text is left out: it could carry the stored value. Anything
  /// thrown counts.
  Future<T> _guard<T>(String what, Future<T> Function() op) async {
    try {
      return await op();
    } on Object {
      throw ApiException('The system keyring could not be $what.');
    }
  }
}
