import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/connection.dart';
import '../core/ports.dart';

/// [SettingsStore] in the system keyring (libsecret), as one entry holding the address and key.
class KeyringSettingsStore implements SettingsStore {
  KeyringSettingsStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _entry = 'anythingllm-connection';

  final FlutterSecureStorage _storage;

  @override
  Future<Connection?> load() async {
    final stored = await _guard('read', () => _storage.read(key: _entry));
    if (stored == null) return null;
    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      return Connection(
        baseUrl: json['baseUrl'] as String,
        apiKey: json['apiKey'] as String,
      );
    } on Object {
      throw const ApiException(
        'The saved connection in the keyring is unreadable. Enter it again and save.',
      );
    }
  }

  @override
  Future<void> save(Connection connection) => _guard(
    'written',
    () => _storage.write(
      key: _entry,
      value: jsonEncode({
        'baseUrl': connection.baseUrl,
        'apiKey': connection.apiKey,
      }),
    ),
  );

  @override
  Future<void> clear() => _guard('written', () => _storage.delete(key: _entry));

  /// Runs [op], and turns any failure into an [ApiException] that says what [what] could not be
  /// done. The exception's own text is left out: it could carry the stored value.
  Future<T> _guard<T>(String what, Future<T> Function() op) async {
    try {
      return await op();
    } on Exception {
      throw ApiException(
        'The system keyring could not be $what. '
        'Is a secret service such as gnome-keyring running and unlocked?',
      );
    }
  }
}
