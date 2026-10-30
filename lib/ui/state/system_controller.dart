import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/connection.dart';
import '../../core/ports.dart';
import '../../core/users.dart';
import 'follows_server.dart';
import 'notice.dart';
import 'read.dart';
import 'settings_controller.dart';

/// The server itself, apart from its workspaces: its settings, how many vectors its database
/// holds, and whether it has several users and who they are. A new server starts it afresh.
class SystemController extends ChangeNotifier with FollowsServer {
  SystemController(this._api, SettingsController settings) {
    followServer(settings);
  }

  final AnythingLlmApi _api;

  /// How many vectors the server holds, or null until read.
  int? vectors;

  /// The settings as last read, which a second ask joins while a read is under way, and a save
  /// keeps over the read under way.
  late final _settings = ReadSlot<Map<String, Object?>>(notifyListeners);

  /// The server's settings, with every secret replaced by whether it is set, or null until read.
  Map<String, Object?>? get settings => _settings.value;

  /// Why the last read or save of the settings failed.
  Notice? get settingsProblem => _settings.problem;

  /// Whether the settings are being saved.
  bool saving = false;

  /// Reads the server's settings afresh, or joins the read under way. It tells the listeners
  /// only once it is answered, so a widget may ask as it opens.
  Future<void> readSettings() async {
    final at = here;
    if (at.server == null) return;
    await _settings.read(
      _api.systemSettings,
      failTitle: 'Could not read the settings',
      current: () => at.current,
      join: true,
      quiet: true,
    );
  }

  /// Reads the server's settings unless they are read already.
  Future<void> wantSettings() async {
    if (settings == null) await readSettings();
  }

  /// Whether [wantSettingsOnce] has asked on this server.
  bool _wanted = false;

  /// Reads the settings unless they are read already, once a server and after the frame, for the
  /// system's chat model beside the composer: a read that failed is asked again on another
  /// server, not on every rebuild.
  void wantSettingsOnce() {
    if (_wanted || server == null) return;
    _wanted = true;
    afterFrame(() => unawaited(wantSettings()));
  }

  /// Writes [changes], each setting by its name as text, and takes them into [settings] once the
  /// server wrote them all; a read already under way is then not kept over them. Returns whether
  /// they were written; why not shows as [settingsProblem].
  Future<bool> saveSettings(Map<String, String> changes) async {
    final at = here;
    final was = settings;
    if (at.server == null || was == null || saving) return false;
    if (changes.isEmpty) return true;
    saving = true;
    notifyListeners();
    Notice? failed;
    try {
      await _api.updateSystem(changes);
    } on ApiException catch (error) {
      failed = Notice('Could not save the settings', error.message);
    }
    if (!at.current) return false;
    if (failed == null) _settings.take({...?settings, ...changes});
    saving = false;
    _settings.problem = failed;
    notifyListeners();
    return failed == null;
  }

  /// Reads how many vectors the server holds after the frame, unless they are read already. A
  /// count that cannot be read is left out where it would show.
  void wantVectors() => afterFrame(() {
    if (vectors == null) unawaited(_readVectors());
  });

  Future<void> _readVectors() async {
    final at = here;
    if (at.server == null) return;
    try {
      final count = await _api.vectorCount();
      if (!at.current) return;
      vectors = count;
      notifyListeners();
    } on ApiException {
      return;
    }
  }

  /// Whether the server has several users, as last read.
  late final _several = ReadSlot<bool>(notifyListeners);

  /// Who has an account on the server, as last read; read only once it has several users.
  late final _people = ReadSlot<List<ServerUser>>(notifyListeners);

  /// Whether the server has several users, or null until read.
  bool? get multiUser => _several.value;

  /// Everyone with an account on the server, empty on a single-user server or until read.
  List<ServerUser> get users => _people.value ?? const [];

  /// Why the last read of whether the server has several users, or of who they are, failed.
  Notice? get usersProblem => _several.problem ?? _people.problem;

  /// Reads whether the server has several users and, when it has, who they are, or joins the
  /// reads under way.
  Future<void> readUsers() async {
    final at = here;
    if (at.server == null) return;
    const failTitle = 'Could not read who uses this server';
    await _several.read(
      _api.multiUser,
      failTitle: failTitle,
      current: () => at.current,
      join: true,
      quiet: true,
    );
    if (!at.current || multiUser != true) return;
    await _people.read(
      _api.users,
      failTitle: failTitle,
      current: () => at.current,
      join: true,
      quiet: true,
    );
  }

  /// Reads the server's users after the frame, unless they are known or being read already. A
  /// read that failed is asked again.
  void wantUsers() => afterFrame(() {
    final known = multiUser == false || _people.value != null;
    if (!known && !_several.loading && !_people.loading) {
      unawaited(readUsers());
    }
  });

  /// The server Who uses this app? is to open on once it is read to have several users, as
  /// after connecting to it.
  Connection? _askedFor;

  /// Asks for Who uses this app? once the server in use is read to have several users, as it is
  /// just after connecting, and reads its users.
  void askWhoUses() {
    _askedFor = server;
    unawaited(readUsers());
  }

  /// Whether Who uses this app? is to open now, once: on the server [askWhoUses] asked about,
  /// once it is read to have several users.
  bool takeWhoUses() {
    final several = multiUser;
    if (_askedFor == null || _askedFor != server || several == null) {
      return false;
    }
    _askedFor = null;
    return several;
  }

  @override
  void serverChanged(_) {
    _wanted = false;
    _askedFor = null;
    _several.reset();
    _people.reset();
    vectors = null;
    // A read still under way is kept should its server be in use again when it is answered.
    _settings.reset(dropRead: false);
    saving = false;
    notifyListeners();
  }
}
