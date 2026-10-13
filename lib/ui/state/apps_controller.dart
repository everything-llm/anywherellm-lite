import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/apps.dart';
import '../../core/ports.dart';
import '../../core/system_files.dart';
import 'chat_controller.dart';
import 'companion_watch.dart';
import 'log_pages.dart';
import 'settings_controller.dart';

/// What the app knows of the apps server beside the server in use: whether it is there
/// ([CompanionWatch.available]) and has System files ([systemFiles]), the open workspace's apps,
/// what one app's folder holds while its data shows, the changes made to an app, and its cards
/// in answers. Another server starts it afresh, and Test connection asks again whether the apps
/// server is there.
class AppsController extends ChangeNotifier with CompanionWatch {
  AppsController(this._api, this._settings, this._chat) {
    _chat.addListener(_chatChanged);
    _chatShown = (_chat.activeSlug, _chat.activeThread);
    watch(_api, _settings);
  }

  final AppsApi _api;
  final SettingsController _settings;
  final ChatController _chat;

  /// The chat on screen, whose cards are read afresh when another opens.
  (String?, String?) _chatShown = (null, null);

  /// Where the apps server's cards and client API are: where they were said to be, or else
  /// beside the AnythingLLM server ([SettingsController.addressOf]).
  Uri? get cards => _settings.addressOf(appsCompanion);

  /// Where the apps server's working pages are, once it is found ([AppsApi.pages]).
  Uri? pages;

  /// Whether the apps server serves System files, as its `/health` says.
  bool get systemFiles => serves(AppsFeature.systemFiles);

  /// Each workspace's apps as last read, by slug.
  final _lists = <String, List<ServerApp>>{};

  /// Why the last read of a workspace's apps failed, by slug.
  final _problems = <String, String>{};

  /// The workspaces whose apps are being read.
  final _reading = <String>{};

  /// Whether the Apps tab has asked for the open workspace's apps, so another workspace's are
  /// read as it opens.
  bool _wanted = false;

  @override
  void serverChanged() {
    pages = null;
    _lists.clear();
    _problems.clear();
    _reading.clear();
    _cards.clear();
    _pictures.clear();
    _wanted = false;
    _forgetData();
  }

  /// Reads the open workspace's apps once the apps server is found, when the Apps tab wanted
  /// them.
  @override
  void detected() {
    final asked = epoch;
    unawaited(
      _api.pages().then((found) {
        if (asked != epoch || found == pages) return;
        pages = found;
        notifyListeners();
      }),
    );
    if (available == true && _wanted) unawaited(read());
  }

  /// The System files folder at [path], `""` for the top, read afresh.
  Future<List<SystemEntry>> systemFolder(String path) =>
      _api.systemFolder(path);

  /// The System files file at [path] as text, or null when it is not text.
  Future<String?> systemFile(String path) => _api.systemFile(path);

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
    final asked = epoch;
    notifyListeners();
    try {
      final found = await _api.apps(workspace);
      if (asked != epoch) return;
      final before = {for (final app in _lists[workspace] ?? []) app.ref: app};
      for (final app in found) {
        final was = before[app.ref];
        if (was != null && !was.sameAs(app)) _changed(app.ref);
      }
      _lists[workspace] = found;
      _problems.remove(workspace);
    } on ApiException catch (error) {
      if (asked != epoch) return;
      _problems[workspace] = error.message;
    } finally {
      if (asked == epoch) {
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

  /// Reads [ref] as it is now, as an app does when it opens: its workspace's apps when they
  /// are not read yet, otherwise [ref] alone (`GET /apps/<workspace>/<name>`), whose
  /// [ServerApp.version] says whether its card and data must be read again. An apps server
  /// without that route, an app it does not know and a failed read fall back to reading the
  /// workspace's apps. After a change, [dataRead] says the app's data is already being read
  /// again.
  Future<void> check(AppRef ref, {bool dataRead = false}) async {
    if (available != true) return;
    if (_reading.contains(ref.workspace)) return;
    if (!_lists.containsKey(ref.workspace)) return read(ref.workspace);
    final asked = epoch;
    ServerApp? found;
    try {
      found = await _api.app(ref);
    } on ApiException {
      found = null;
    }
    if (asked != epoch) return;
    final list = _lists[ref.workspace];
    final at = list?.indexWhere((app) => app.ref == ref) ?? -1;
    if (found == null || list == null || at < 0) return read(ref.workspace);
    if (!list[at].sameAs(found)) _changed(ref, dataRead: dataRead);
    _lists[ref.workspace] = appsInOrder([...list]..[at] = found);
    notifyListeners();
  }

  /// Lets go of what is read of [ref], which changed: its cards, and its data unless
  /// [dataRead].
  void _changed(AppRef ref, {bool dataRead = false}) {
    _dropCard(ref);
    if (_data == ref && !dataRead) {
      _forgetData();
      _data = ref;
      dataRevision++;
    }
  }

  // ---- One app's folder, while its data shows.

  AppRef? _data;
  Future<List<AppFile>>? _files;
  final _texts = <String, Future<String>>{};
  LogPages? _log;
  Future<List<AppCommit>>? _commits;
  final _diffs = <String, Future<AppDiff>>{};
  final _states = <int?, Future<AppState>>{};

  /// Counts the changes to the app whose data shows, so its pages read it again.
  int dataRevision = 0;

  void _forgetData() {
    _data = null;
    _files = null;
    _texts.clear();
    _log?.leave();
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

  /// [app]'s log, newest line first, read a page at a time from its newest.
  LogPages log(AppRef app) {
    _for(app);
    return _log ??= LogPages(_api, app)..start();
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

  /// [app]'s commit [commit], whole and file by file.
  Future<AppDiff> diff(AppRef app, String commit) {
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
      unawaited(check(app, dataRead: true));
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

  /// Each card's last picture and its `ETag`, by the address read, kept when the card is let
  /// go of so that reading it again costs no picture while it has not changed.
  final _pictures = <Uri, CardPicture>{};

  /// The card at [card] as one picture, light or dark, read once until the app changes or
  /// another chat opens, or read afresh when [fresh], as when its chat shows again. A card
  /// read again sends the last one's `ETag`, and keeps its picture when the server answers
  /// that it has not changed.
  Future<Uint8List> card(Uri card, {required bool light, bool fresh = false}) {
    final url = onceCard(card, light: light);
    if (fresh) _cards.remove(url);
    final asked = epoch;
    return _cards[url] ??= _api
        .card(url, last: _pictures[url])
        .then(
          (picture) {
            if (asked == epoch) _pictures[url] = picture;
            return picture.bytes;
          },
          onError: (Object error) {
            _cards.remove(url);
            throw error;
          },
        );
  }

  void _dropCard(AppRef app) {
    final at = cards;
    _cards.removeWhere((url, _) => appCardRef(url, at) == app);
  }

  @override
  void dispose() {
    unwatch();
    _chat.removeListener(_chatChanged);
    super.dispose();
  }
}
