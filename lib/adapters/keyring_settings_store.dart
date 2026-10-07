import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/connection.dart';
import '../core/ports.dart';

/// [SettingsStore] in the system keyring (libsecret on Linux, the Android Keystore on Android), as
/// one entry holding the address, the key and the server's password when one is saved. In a
/// browser the entry is in the page's local storage, encrypted with a key kept beside it, so it is
/// as safe as the browser profile and no safer; the browser's encryption needs https or localhost.
class KeyringSettingsStore implements SettingsStore {
  KeyringSettingsStore({FlutterSecureStorage? storage, this.failureHint = ''})
    : _storage = storage ?? const FlutterSecureStorage();

  /// What to check when the keyring fails, after a space, or empty.
  final String failureHint;

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
      ).withPassword(json['password'] as String?);
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
        'password': ?connection.password,
      }),
    ),
  );

  @override
  Future<void> clear() => _guard('written', () => _storage.delete(key: _entry));

  /// Runs [op], and turns any failure into an [ApiException] that says what [what] could not be
  /// done. The exception's own text is left out: it could carry the stored value. A browser's
  /// failure can be a JavaScript error rather than an [Exception], so anything thrown counts.
  Future<T> _guard<T>(String what, Future<T> Function() op) async {
    try {
      return await op();
    } on Object {
      throw ApiException('The system keyring could not be $what.$failureHint');
    }
  }
}
