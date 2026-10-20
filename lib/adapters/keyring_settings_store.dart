import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/connection.dart';
import '../core/ports.dart';
import '../core/toolkit.dart';

/// [SettingsStore] in the Android Keystore, as one entry holding the address, the key and where
/// its companions run, when said. An entry an older version saved with the server's password,
/// or with a companion's address under the name its `/health` gave, is written again as this
/// version keeps it ([companionKey]).
class KeyringSettingsStore implements SettingsStore {
  KeyringSettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _entry = 'anythingllm-connection';

  final FlutterSecureStorage _storage;

  @override
  Future<Pairing?> load() async {
    final stored = await _guard('read', () => _storage.read(key: _entry));
    if (stored == null) return null;
    final Connection connection;
    final Map<String, Uri> companions;
    final bool outdated;
    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      connection = Connection(
        baseUrl: json['baseUrl'] as String,
        apiKey: json['apiKey'] as String,
      );
      final named = json['companions'];
      companions = {
        if (named is Map)
          for (final MapEntry(:key, :value) in named.entries)
            // An address that cannot be read leaves that companion out, not the connection.
            if (key is String && value is String && Uri.tryParse(value) != null)
              companionKey(key): Uri.parse(value),
      };
      outdated =
          json.containsKey('password') ||
          (named is Map &&
              named.keys.any((key) => companionKey('$key') != key));
    } on Object {
      throw const ApiException(
        'The saved connection in the keyring is unreadable. Enter it again and save.',
      );
    }
    if (outdated) {
      try {
        await save(Pairing(connection, companions));
      } on ApiException {
        // The entry is written again on the next save; the connection works meanwhile.
      }
    }
    return Pairing(connection, companions);
  }

  @override
  Future<void> save(Pairing saved) => _guard(
    'written',
    () => _storage.write(
      key: _entry,
      value: jsonEncode({
        'baseUrl': saved.connection.baseUrl,
        'apiKey': saved.connection.apiKey,
        if (saved.companions.isNotEmpty)
          'companions': {
            for (final MapEntry(:key, :value) in saved.companions.entries)
              key: '$value',
          },
      }),
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
