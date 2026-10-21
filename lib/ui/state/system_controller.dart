import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ports.dart';
import 'follows_server.dart';
import 'notice.dart';
import 'read.dart';
import 'settings_controller.dart';

/// The server itself, apart from its workspaces: its settings and how many vectors its database
/// holds. A new server starts it afresh.
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

  @override
  void serverChanged(_) {
    _wanted = false;
    vectors = null;
    // A read still under way is kept should its server be in use again when it is answered.
    _settings.reset(dropRead: false);
    saving = false;
    notifyListeners();
  }
}
