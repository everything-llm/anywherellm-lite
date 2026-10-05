import 'package:flutter/foundation.dart';

import '../../core/connection.dart';
import '../../core/ports.dart';
import 'notice.dart';

enum ConnectionCheck { idle, testing, ok, failed }

/// The AnythingLLM address and key: the one in use, testing a candidate, saving and removing.
class SettingsController extends ChangeNotifier {
  /// Keeps the connection in use in [holder], where the client reads it.
  SettingsController(this._api, this._store, this._holder);

  final AnythingLlmApi _api;
  final SettingsStore _store;
  final ConnectionHolder _holder;

  /// The connection in use, or null before one is saved.
  Connection? get connection => _holder.current;

  ConnectionCheck check = ConnectionCheck.idle;

  /// What the last test or save said.
  String? message;

  /// Why the keyring could not be read or written. The connection still works for this run.
  Notice? keyringProblem;

  bool get configured => connection != null;

  /// Reads the saved connection. A keyring that cannot be read is a notice, not a failure to
  /// start.
  Future<void> load() async {
    await _keyring('Could not read the saved connection', () async {
      _holder.current = await _store.load();
    });
    notifyListeners();
  }

  /// Asks the server whether [url] and [key] open it. Saves nothing.
  Future<void> test(String url, String key) async {
    final candidate = _parse(url, key);
    if (candidate == null) return;
    check = ConnectionCheck.testing;
    message = null;
    notifyListeners();
    try {
      await _api.verify(candidate);
      check = ConnectionCheck.ok;
      message = 'Connected to ${candidate.host}.';
    } on ApiException catch (error) {
      check = ConnectionCheck.failed;
      message = error.message;
    }
    notifyListeners();
  }

  /// Saves [url] and [key] only once the server accepts them. True when it did.
  Future<bool> connect(String url, String key) async {
    await test(url, key);
    if (check != ConnectionCheck.ok) return false;
    await save(url, key);
    return true;
  }

  /// Uses [url] and [key] from now on and keeps them in the keyring. If the keyring refuses,
  /// they are still used for this run and the refusal is shown.
  Future<void> save(String url, String key) async {
    final candidate = _parse(url, key);
    if (candidate == null) return;
    _holder.current = candidate;
    check = ConnectionCheck.idle;
    await _keyring(
      'Could not save the connection',
      () => _store.save(candidate),
    );
    message = keyringProblem == null ? 'The key was saved.' : null;
    notifyListeners();
  }

  /// Forgets the connection and removes it from the keyring.
  Future<void> clear() async {
    _holder.current = null;
    check = ConnectionCheck.idle;
    await _keyring(
      'Could not remove the saved connection',
      () => _store.clear(),
    );
    message = keyringProblem == null ? 'The saved key was deleted.' : null;
    notifyListeners();
  }

  /// Runs a keyring [op], and records why it failed in [keyringProblem], or clears it.
  Future<void> _keyring(String failTitle, Future<void> Function() op) async {
    try {
      await op();
      keyringProblem = null;
    } on ApiException catch (error) {
      keyringProblem = Notice(failTitle, error.message);
    }
  }

  /// The connection [url] and [key] describe, or null after saying what is wrong with them.
  Connection? _parse(String url, String key) {
    try {
      return Connection.parse(url, key);
    } on ApiException catch (error) {
      check = ConnectionCheck.failed;
      message = error.message;
      notifyListeners();
      return null;
    }
  }
}
