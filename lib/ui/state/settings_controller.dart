import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/connection.dart';
import '../../core/ports.dart';
import 'notice.dart';

enum ConnectionCheck { idle, testing, ok, failed }

/// The AnythingLLM address and key: the one in use, testing a candidate, signing in to get one,
/// saving and removing; and the server's password, for the web UI's own routes, when the server
/// has one. Listeners
/// hear of a new connection as soon as the client uses it, before the keyring has written it.
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

  /// How the server in use signs in to its web UI, or null until it has said or when asking
  /// failed. Settings asks for the password when it is [ServerAuth.password].
  ServerAuth? auth;

  /// Whether a password is being checked.
  bool checkingPassword = false;

  /// What the last password save or removal said.
  String? passwordMessage;

  /// Whether the last [signIn] found a server that gives no key that way, so Settings asks for
  /// one.
  bool needsKey = false;

  /// Reads the saved connection, then asks its server how it signs in. A keyring that cannot be
  /// read is a notice, not a failure to start.
  Future<void> load() async {
    await _keyring('Could not read the saved connection', () async {
      _holder.current = await _store.load();
    });
    notifyListeners();
    unawaited(readAuth());
  }

  /// Asks the server whether [url] and [key] open it. Saves nothing.
  Future<void> test(String url, String key) async {
    final candidate = _parse(url, key);
    if (candidate != null) await _check(candidate);
  }

  /// How many times Test connection has asked about the saved connection, so what remembers
  /// an answer per connection, such as whether the apps server is there, asks again.
  int tests = 0;

  /// Asks the server whether the saved connection still opens it, then how it signs in.
  Future<void> testSaved() async {
    final server = connection;
    if (server == null) return;
    tests++;
    await _check(server);
    if (connection != server) return;
    await readAuth();
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
    await test(url, key);
    if (check != ConnectionCheck.ok) return false;
    await save(url, key);
    return true;
  }

  /// Uses [url] and [key] from now on and keeps them in the keyring, with the saved password
  /// when the address is the same. If the keyring refuses, they are still used for this run and
  /// the refusal is shown.
  Future<void> save(String url, String key) async {
    final parsed = _parse(url, key);
    if (parsed == null) return;
    final kept = connection;
    await _use(
      kept != null && kept.baseUrl == parsed.baseUrl
          ? parsed.withPassword(kept.password)
          : parsed,
      'The key was saved.',
    );
  }

  /// Connects to the server at [url] with its [password], ignored when the server has none.
  /// The server gives the app its developer key, which is saved with the password once it opens
  /// the server. True when it was. A server with several users gives no key, and [needsKey] then
  /// says to paste one.
  Future<bool> signIn(String url, String password) async {
    final String baseUrl;
    try {
      baseUrl = normalizeBaseUrl(url);
    } on ApiException catch (error) {
      check = ConnectionCheck.failed;
      message = error.message;
      notifyListeners();
      return false;
    }
    check = ConnectionCheck.testing;
    message = null;
    needsKey = false;
    notifyListeners();
    final Connection candidate;
    try {
      final found = await _api.serverAuth(
        Connection(baseUrl: baseUrl, apiKey: ''),
      );
      if (found == ServerAuth.multiUser) {
        needsKey = true;
        throw const ApiException(
          'This server has several users, so it gives no key this way. Use a developer key '
          'its admin made.',
        );
      }
      final signsIn = found == ServerAuth.password;
      if (signsIn && password.isEmpty) {
        throw const ApiException('Enter the server password.');
      }
      final key = await _api.issueKey(
        baseUrl,
        password: signsIn ? password : null,
      );
      candidate = Connection.parse(
        baseUrl,
        key,
        password: signsIn ? password : null,
      );
      await _api.verify(candidate);
    } on ApiException catch (error) {
      check = ConnectionCheck.failed;
      message = error.message;
      notifyListeners();
      return false;
    }
    await _use(candidate, 'Signed in to ${candidate.host}.');
    return true;
  }

  /// Uses [candidate] from now on and keeps it in the keyring, saying [saved] once it is there.
  /// If the keyring refuses, it is still used for this run and the refusal is shown.
  Future<void> _use(Connection candidate, String saved) async {
    final kept = connection;
    if (kept?.baseUrl != candidate.baseUrl) auth = null;
    passwordMessage = null;
    _holder.current = candidate;
    check = ConnectionCheck.idle;
    notifyListeners();
    await _keyring(
      'Could not save the connection',
      () => _store.save(candidate),
    );
    message = keyringProblem == null ? saved : null;
    notifyListeners();
    unawaited(readAuth());
  }

  /// Uses [password] for the server in use from now on, once the server takes it, and keeps it
  /// in the keyring with the key. True when it was saved.
  Future<bool> savePassword(String password) async {
    final current = connection;
    if (current == null) return false;
    if (password.isEmpty) {
      passwordMessage = 'Enter the password.';
      notifyListeners();
      return false;
    }
    final candidate = current.withPassword(password);
    checkingPassword = true;
    passwordMessage = null;
    notifyListeners();
    try {
      await _api.signIn(candidate);
    } on ApiException catch (error) {
      checkingPassword = false;
      passwordMessage = error.message;
      notifyListeners();
      return false;
    }
    checkingPassword = false;
    if (connection != current) {
      notifyListeners();
      return false;
    }
    _holder.current = candidate;
    notifyListeners();
    await _keyring('Could not save the password', () => _store.save(candidate));
    passwordMessage = keyringProblem == null ? 'The password was saved.' : null;
    notifyListeners();
    return true;
  }

  /// Stops using the saved password and removes it from the keyring; the key stays.
  Future<void> forgetPassword() async {
    final current = connection;
    if (current == null || current.password == null) return;
    final candidate = current.withPassword(null);
    _holder.current = candidate;
    notifyListeners();
    await _keyring(
      'Could not remove the saved password',
      () => _store.save(candidate),
    );
    passwordMessage = keyringProblem == null
        ? 'The saved password was deleted.'
        : null;
    notifyListeners();
  }

  /// Asks the server in use how it signs in, into [auth]. Best effort: a failure leaves it null,
  /// and Settings then asks for nothing until it is asked again.
  Future<void> readAuth() async {
    final server = connection;
    if (server == null) return;
    ServerAuth? found;
    try {
      found = await _api.serverAuth(server);
    } on ApiException {
      found = null;
    }
    if (connection?.baseUrl != server.baseUrl || found == auth) return;
    auth = found;
    notifyListeners();
  }

  /// Forgets the connection and removes it from the keyring.
  Future<void> clear() async {
    _holder.current = null;
    auth = null;
    needsKey = false;
    passwordMessage = null;
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
