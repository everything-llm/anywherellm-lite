import 'package:flutter/foundation.dart';

import '../../core/connection.dart';
import '../../core/ports.dart';
import 'notice.dart';

enum ConnectionCheck { idle, testing, ok, failed }

/// A field of the form that connects: the server's address, or the developer key.
enum ConnectionField { address, key }

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

  /// Whether [check] is of the connection in use, as [testSaved]'s is, rather than of one being
  /// tried before it is saved.
  bool checkedInUse = false;

  /// What the last test or save said.
  String? message;

  /// The field of the typed address and key that [message] says is wrong, or null when it is
  /// about neither, as a pairing code's or a saved connection's test is.
  ConnectionField? wrong;

  /// What [connect] says of a key the server would not take, under the key.
  static const keyRefused =
      'That key didn\u2019t work. Copy it again from AnythingLLM\u2019s settings.';

  /// What [connect] says of an address no connection could be made to, under the address.
  static const notReached =
      'Can\u2019t reach that address. Check it opens in a browser on this phone.';

  /// Why the keyring could not be read or written. The connection still works for this run.
  Notice? keyringProblem;

  bool get configured => connection != null;

  /// Reads the saved connection. A keyring that cannot be read is a notice, not a failure to
  /// start.
  Future<void> load() async {
    await _keyring('Could not read the saved connection', () async {
      if (await _store.load() case final saved?) _holder.current = saved;
    });
    notifyListeners();
  }

  /// Connects to [pairing], a pairing code's connection, once the server takes its key. True
  /// when it did.
  Future<bool> pair(Connection pairing) => _connect(pairing);

  /// Asks the server whether the saved connection still opens it.
  Future<void> testSaved() async {
    final server = connection;
    if (server == null) return;
    await _check(server);
  }

  /// Counts the tests started and the connections put in use or forgotten, so the answer to a
  /// test that is no longer the latest is dropped.
  int _checks = 0;

  /// Asks the server whether [candidate] opens it, into [check] and [message]. True when it did
  /// and said so; an answer that comes after another test began, or the connection in use changed,
  /// says nothing and is false.
  /// When [typed], a failure names the field it is about in [wrong], in the words the form says
  /// it in.
  Future<bool> _check(Connection candidate, {bool typed = false}) async {
    final go = ++_checks;
    check = ConnectionCheck.testing;
    checkedInUse = candidate == connection;
    message = null;
    wrong = null;
    notifyListeners();
    ApiException? failed;
    try {
      await _api.verify(candidate);
    } on ApiException catch (error) {
      failed = error;
    }
    if (go != _checks) return false;
    check = failed == null ? ConnectionCheck.ok : ConnectionCheck.failed;
    message = switch (failed) {
      null => 'Connected to ${candidate.host}.',
      KeyRefused() when typed => keyRefused,
      Unreachable() when typed => notReached,
      ApiException(:final message) => message,
    };
    if (typed && failed != null) {
      wrong = failed is KeyRefused
          ? ConnectionField.key
          : ConnectionField.address;
    }
    notifyListeners();
    return failed == null;
  }

  /// Saves [url] and [key] only once the server accepts them. True when it did. A failure names
  /// the field it is about ([wrong]).
  Future<bool> connect(String url, String key) async {
    final candidate = _parse(url, key);
    return candidate != null && await _connect(candidate, typed: true);
  }

  /// Uses [candidate] once the server takes its key.
  Future<bool> _connect(Connection candidate, {bool typed = false}) async {
    if (!await _check(candidate, typed: typed)) return false;
    await _use(candidate, 'The key was saved.');
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
  /// If the keyring refuses, it is still used for this run and the refusal is shown.
  Future<void> _use(Connection candidate, String saved) async {
    _holder.current = candidate;
    _checks++;
    check = ConnectionCheck.idle;
    wrong = null;
    notifyListeners();
    await _keyring(
      'Could not save the connection',
      () => _store.save(candidate),
    );
    message = keyringProblem == null ? saved : null;
    notifyListeners();
  }

  /// Forgets the connection and removes it from the keyring.
  Future<void> clear() async {
    _holder.current = null;
    _checks++;
    check = ConnectionCheck.idle;
    wrong = null;
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

  /// The connection [url] and [key] describe, or null after saying what is wrong with them and
  /// which of them it is ([wrong]): the address first.
  Connection? _parse(String url, String key) {
    var field = ConnectionField.address;
    try {
      normalizeBaseUrl(url);
      field = ConnectionField.key;
      return Connection.parse(url, key);
    } on ApiException catch (error) {
      check = ConnectionCheck.failed;
      checkedInUse = false;
      message = error.message;
      wrong = field;
      notifyListeners();
      return null;
    }
  }
}
