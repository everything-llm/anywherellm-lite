import 'package:flutter/foundation.dart';

import '../../core/companion.dart';
import '../../core/connection.dart';
import '../../core/ports.dart';
import 'notice.dart';

enum ConnectionCheck { idle, testing, ok, failed }

/// The AnythingLLM address and developer key: the one in use, testing a candidate, saving and
/// removing. Listeners hear of a new connection as soon as the client uses it, before the
/// keyring has written it.
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
      if (await _store.load() case final saved?) {
        _holder
          ..current = saved.connection
          ..companions = saved.companions;
      }
    });
    notifyListeners();
  }

  /// Where [companion] runs beside the server in use: as said, or else [Companion.base]'s
  /// guess. Null with no server.
  Uri? addressOf(Companion companion) => _holder.addressOf(companion);

  /// Connects as [pairing] says, once the server takes its key, keeping where its companions
  /// run. True when it did.
  Future<bool> pair(Pairing pairing) =>
      _connect(pairing.connection, pairing.companions);

  /// Asks the server whether [url] and [key] open it. Saves nothing.
  Future<void> test(String url, String key) async {
    final candidate = _parse(url, key);
    if (candidate != null) await _check(candidate);
  }

  /// How many times Test connection has asked about the saved connection, so what remembers
  /// an answer per connection, such as whether the apps server is there, asks again.
  int tests = 0;

  /// Asks the server whether the saved connection still opens it.
  Future<void> testSaved() async {
    final server = connection;
    if (server == null) return;
    tests++;
    await _check(server);
  }

  /// Asks the server whether [candidate] opens it, into [check] and [message].
  Future<void> _check(Connection candidate) async {
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
    final candidate = _parse(url, key);
    return candidate != null && await _connect(candidate, null);
  }

  /// Uses [candidate] once the server takes its key, with [companions] as in [_use].
  Future<bool> _connect(
    Connection candidate,
    Map<String, Uri>? companions,
  ) async {
    await _check(candidate);
    if (check != ConnectionCheck.ok) return false;
    await _use(candidate, 'The key was saved.', companions: companions);
    return true;
  }

  /// Uses [url] and [key] from now on and keeps them in the keyring. If the keyring refuses,
  /// they are still used for this run and the refusal is shown.
  Future<void> save(String url, String key) async {
    final parsed = _parse(url, key);
    if (parsed == null) return;
    await _use(parsed, 'The key was saved.');
  }

  /// Uses [candidate] from now on and keeps it in the keyring, saying [saved] once it is there.
  /// Where companions run is [companions] when given, kept when the server's address stays, and
  /// forgotten for another server. If the keyring refuses, it is still used for this run and
  /// the refusal is shown.
  Future<void> _use(
    Connection candidate,
    String saved, {
    Map<String, Uri>? companions,
  }) async {
    final kept = connection?.baseUrl == candidate.baseUrl
        ? _holder.companions
        : const <String, Uri>{};
    _holder
      ..current = candidate
      ..companions = companions ?? kept;
    check = ConnectionCheck.idle;
    notifyListeners();
    await _keyring(
      'Could not save the connection',
      () => _store.save(Pairing(candidate, _holder.companions)),
    );
    message = keyringProblem == null ? saved : null;
    notifyListeners();
  }

  /// Forgets the connection and removes it from the keyring.
  Future<void> clear() async {
    _holder
      ..current = null
      ..companions = const {};
    check = ConnectionCheck.idle;
    notifyListeners();
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
