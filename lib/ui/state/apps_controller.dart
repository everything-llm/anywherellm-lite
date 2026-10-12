import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/apps.dart';
import '../../core/connection.dart';
import '../../core/ports.dart';
import 'chat_controller.dart';
import 'settings_controller.dart';

/// What the app knows of the apps server beside the server in use: whether it is there
/// ([available]), the open workspace's apps, what one app's folder holds while its data shows,
/// the changes made to an app, and its cards in answers. Another server starts it afresh, and
/// Test connection asks again whether the apps server is there.
class AppsController extends ChangeNotifier {
  AppsController(this._api, this._settings, this._chat) {
    _settings.addListener(_settingsChanged);
    _chat.addListener(_chatChanged);
    _server = _key(_settings.connection);
    _tests = _settings.tests;
    _chatShown = (_chat.activeSlug, _chat.activeThread);
    if (_server != null) unawaited(_detect());
  }

  final AppsApi _api;
  final SettingsController _settings;
  final ChatController _chat;

  /// The server in use, by its address and key: its password does not touch the apps server.
  Connection? _server;
  int _tests = 0;

  /// The chat on screen, whose cards are read afresh when another opens.
  (String?, String?) _chatShown = (null, null);

  /// Whether the apps server answers beside the server in use: null until it is asked.
  bool? available;

  /// Each workspace's apps as last read, by slug.
  final _lists = <String, List<ServerApp>>{};

  /// Why the last read of a workspace's apps failed, by slug.
  final _problems = <String, String>{};

  /// The workspaces whose apps are being read.
  final _reading = <String>{};

  /// Whether the Apps tab has asked for the open workspace's apps, so another workspace's are
  /// read as it opens.
  bool _wanted = false;

  /// Counts the connection changes, so an answer from the server before is dropped.
  int _epoch = 0;

  static Connection? _key(Connection? connection) =>
      connection?.withPassword(null);

  void _settingsChanged() {
    final here = _key(_settings.connection);
    if (here != _server) {
      _server = here;
      _tests = _settings.tests;
      _reset();
      if (here != null) unawaited(_detect());
      return;
    }
    if (_settings.tests != _tests) {
      _tests = _settings.tests;
      if (here != null) unawaited(_detect(again: true));
    }
  }

  void _reset() {
    _epoch++;
    available = null;
    _lists.clear();
    _problems.clear();
    _reading.clear();
    _cards.clear();
    _wanted = false;
    _forgetData();
    notifyListeners();
  }

  /// Asks whether the apps server is there, and reads the open workspace's apps when it is and
  /// the Apps tab wanted them.
  Future<void> _detect({bool again = false}) async {
    final epoch = _epoch;
    final found = await _api.available(again: again);
    if (epoch != _epoch) return;
    if (found == available) return;
    available = found;
    notifyListeners();
    if (found && _wanted) unawaited(read());
  }

  void _chatChanged() {
    final shown = (_chat.activeSlug, _chat.activeThread);
    if (shown == _chatShown) return;
    final workspace = shown.$1 != _chatShown.$1;
    _chatShown = shown;
    // A chat opened again shows each app as it is now.
    _cards.clear();
    if (workspace && _wanted && available == true) unawaited(read());
  }

  /// The open workspace's apps, or null before they are read.
  List<ServerApp>? get apps => switch (_chat.activeSlug) {
    final slug? => _lists[slug],
    null => null,
  };

  /// Why the open workspace's apps could not be read, or null.
  String? get problem => switch (_chat.activeSlug) {
    final slug? => _problems[slug],
    null => null,
  };

  /// Whether the open workspace's apps are being read.
  bool get reading => _reading.contains(_chat.activeSlug);

  /// Reads the open workspace's apps, as the Apps tab does each time it shows, and from then on
  /// another workspace's as it opens.
  Future<void> want() async {
    _wanted = true;
    if (available == true) await read();
  }

  /// Reads workspace [slug]'s apps, the open workspace's when null.
  Future<void> read([String? slug]) async {
    final workspace = slug ?? _chat.activeSlug;
    if (workspace == null || available != true) return;
    if (!_reading.add(workspace)) return;
    final epoch = _epoch;
    notifyListeners();
    try {
      final found = await _api.apps(workspace);
      if (epoch != _epoch) return;
      final before = {for (final app in _lists[workspace] ?? []) app.ref: app};
      for (final app in found) {
        final was = before[app.ref];
        if (was != null && !was.sameAs(app)) _dropCard(app.ref);
      }
      _lists[workspace] = found;
      _problems.remove(workspace);
    } on ApiException catch (error) {
      if (epoch != _epoch) return;
      _problems[workspace] = error.message;
    } finally {
      if (epoch == _epoch) {
        _reading.remove(workspace);
        notifyListeners();
      }
    }
  }

  /// [ref] as last read, or a stand-in titled by its name before its workspace's apps are.
  ServerApp appOf(AppRef ref) {
    for (final app in _lists[ref.workspace] ?? const <ServerApp>[]) {
      if (app.ref == ref) return app;
    }
    final server = _settings.connection?.uri ?? Uri();
    return ServerApp.unread(ref, server);
  }

  /// Whether [ref]'s workspace's apps are read, or being read; reads them when not.
  void know(AppRef ref) {
    if (_lists.containsKey(ref.workspace) || _reading.contains(ref.workspace)) {
      return;
    }
    unawaited(read(ref.workspace));
  }

  // ---- One app's folder, while its data shows.

  AppRef? _data;
  Future<List<AppFile>>? _files;
  final _texts = <String, Future<String>>{};
  Future<List<LogLine>>? _log;
  Future<List<AppCommit>>? _commits;
  final _diffs = <String, Future<String>>{};
  final _states = <int?, Future<AppState>>{};

  /// Counts the changes to the app whose data shows, so its pages read it again.
  int dataRevision = 0;

  void _forgetData() {
    _data = null;
    _files = null;
    _texts.clear();
    _log = null;
    _commits = null;
    _diffs.clear();
    _states.clear();
  }

  /// Keeps what is read of [app], forgetting another app's.
  void _for(AppRef app) {
    if (_data == app) return;
    _forgetData();
    _data = app;
  }

  /// The files of [app]'s folder, read once until it changes.
  Future<List<AppFile>> files(AppRef app) {
    _for(app);
    return _files ??= _api.files(app);
  }

  /// The text of [app]'s file at [path].
  Future<String> text(AppRef app, String path) {
    _for(app);
    return _texts[path] ??= _api.file(app, path);
  }

  /// [app]'s log, newest line first.
  Future<List<LogLine>> log(AppRef app) {
    _for(app);
    return _log ??= _api.file(app, 'log.jsonl').then(logLinesOf);
  }

  /// [app]'s data after line [line], or now when null.
  Future<AppState> state(AppRef app, int? line) {
    _for(app);
    return _states[line] ??= _api.state(app, line: line);
  }

  /// [app]'s commits, newest first.
  Future<List<AppCommit>> commits(AppRef app) {
    _for(app);
    return _commits ??= _api.history(app);
  }

  /// `git show` of [app]'s commit [commit].
  Future<String> diff(AppRef app, String commit) {
    _for(app);
    return _diffs[commit] ??= _api.diff(app, commit);
  }

  // ---- Changes.

  /// Whether a change is being sent.
  bool busy = false;

  /// Why the last change failed, or null.
  String? changeProblem;

  /// Clears [changeProblem], as a sheet does when it opens.
  void clearProblem() {
    if (changeProblem == null) return;
    changeProblem = null;
    notifyListeners();
  }

  /// Does [change], then reads [app] again, its card included. True when it worked; otherwise
  /// [changeProblem] says why.
  Future<bool> _change(AppRef app, Future<void> Function() change) async {
    if (busy) return false;
    busy = true;
    changeProblem = null;
    notifyListeners();
    try {
      await change();
      return true;
    } on ApiException catch (error) {
      changeProblem = error.message;
      return false;
    } finally {
      busy = false;
      if (_data == app) {
        _forgetData();
        _data = app;
      }
      dataRevision++;
      _dropCard(app);
      notifyListeners();
      unawaited(read(app.workspace));
    }
  }

  /// Puts [app]'s data back as it was after line [line].
  Future<bool> restore(AppRef app, int line) =>
      _change(app, () => _api.restore(app, line));

  /// Reverts [app]'s commit [commit].
  Future<bool> revert(AppRef app, String commit) =>
      _change(app, () => _api.revert(app, commit));

  /// Gives [app] the title [title]. An empty title is refused here.
  Future<bool> rename(AppRef app, String title) async {
    final name = title.trim();
    if (name.isEmpty) {
      changeProblem = 'Give it a name.';
      notifyListeners();
      return false;
    }
    return _change(app, () => _api.rename(app, name));
  }

  /// Deletes [app] and takes it out of its workspace's list at once.
  Future<bool> delete(AppRef app) async {
    final done = await _change(app, () => _api.delete(app));
    if (done) {
      final list = _lists[app.workspace];
      if (list != null) {
        _lists[app.workspace] = [
          for (final kept in list)
            if (kept.ref != app) kept,
        ];
        notifyListeners();
      }
    }
    return done;
  }

  // ---- Cards in answers.

  /// Each card read once, by the address read.
  final _cards = <Uri, Future<Uint8List>>{};

  /// The card at [card] as one picture, light or dark, read once until the app changes or
  /// another chat opens, or read afresh when [fresh], as when its chat shows again.
  Future<Uint8List> card(Uri card, {required bool light, bool fresh = false}) {
    final url = onceCard(card, light: light);
    if (fresh) _cards.remove(url);
    return _cards[url] ??= _api.card(url).catchError((Object error) {
      _cards.remove(url);
      throw error;
    });
  }

  void _dropCard(AppRef app) {
    final server = _settings.connection?.uri;
    _cards.removeWhere((url, _) => appCardRef(url, server) == app);
  }

  @override
  void dispose() {
    _settings.removeListener(_settingsChanged);
    _chat.removeListener(_chatChanged);
    super.dispose();
  }
}
