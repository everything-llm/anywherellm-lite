import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../core/connection.dart';
import '../../core/ports.dart';
import 'notice.dart';
import 'settings_controller.dart';

/// The server itself, apart from its workspaces: its settings and how many vectors its database
/// holds. A new server starts it afresh.
class SystemController extends ChangeNotifier {
  SystemController(this._api, this._settings) : _server = _settings.connection {
    _settings.addListener(_serverChanged);
  }

  final AnythingLlmApi _api;
  final SettingsController _settings;

  /// The connection the fields below describe.
  Connection? _server;

  /// How many vectors the server holds, or null until read.
  int? vectors;

  /// The server's settings, with every secret replaced by whether it is set, or null until read.
  Map<String, Object?>? settings;

  /// Why the last read or save of the settings failed.
  Notice? settingsProblem;

  /// Whether the settings are being saved.
  bool saving = false;

  /// The read of the settings under way, which a second ask joins.
  Future<void>? _reading;

  /// Counts the reads of the settings started, so an answer is kept only when no read started
  /// after it, as a save's does.
  var _settingsReads = 0;

  /// Reads the server's settings afresh, or joins the read under way.
  Future<void> readSettings() {
    if (_reading case final reading?) return reading;
    late final Future<void> reading;
    reading = _reading = _readSettings().whenComplete(() {
      if (identical(_reading, reading)) _reading = null;
    });
    return reading;
  }

  /// Reads the server's settings unless they are read already.
  Future<void> wantSettings() async {
    if (settings == null) await readSettings();
  }

  /// Whether [wantSettingsOnce] has asked on this server.
  bool _wanted = false;

  /// Reads the settings unless they are read already, once a server, for the system's chat
  /// model beside the composer: a read that failed is asked again on another server, not on
  /// every rebuild. It asks after the frame, since a read tells this controller's listeners at
  /// once, so a build may call it.
  void wantSettingsOnce() {
    if (_wanted || _server == null) return;
    _wanted = true;
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => unawaited(wantSettings()),
    );
  }

  Future<void> _readSettings() async {
    final server = _server;
    if (server == null) return;
    final number = ++_settingsReads;
    try {
      final read = await _api.systemSettings();
      if (_server != server || number != _settingsReads) return;
      settings = read;
      settingsProblem = null;
    } on ApiException catch (error) {
      if (_server != server || number != _settingsReads) return;
      settingsProblem = Notice('Could not read the settings', error.message);
    }
    notifyListeners();
  }

  /// Writes [changes], each setting by its name as text, and takes them into [settings] once the
  /// server wrote them all; a read already under way is then not kept over them. Returns whether
  /// they were written; why not shows as [settingsProblem].
  Future<bool> saveSettings(Map<String, String> changes) async {
    final server = _server;
    final was = settings;
    if (server == null || was == null || saving) return false;
    if (changes.isEmpty) return true;
    saving = true;
    notifyListeners();
    Notice? failed;
    try {
      await _api.updateSystem(changes);
    } on ApiException catch (error) {
      failed = Notice('Could not save the settings', error.message);
    }
    if (_server != server) return false;
    if (failed == null) {
      _settingsReads++;
      settings = {...?settings, ...changes};
    }
    saving = false;
    settingsProblem = failed;
    notifyListeners();
    return failed == null;
  }

  /// Reads how many vectors the server holds. A count that cannot be read is left out where it
  /// would show.
  Future<void> readVectors() async {
    final server = _server;
    if (server == null) return;
    try {
      final count = await _api.vectorCount();
      if (_server != server) return;
      vectors = count;
      notifyListeners();
    } on ApiException {
      return;
    }
  }

  void _serverChanged() {
    final now = _settings.connection;
    if (now == _server) return;
    _server = now;
    _reading = null;
    _wanted = false;
    vectors = null;
    settings = null;
    settingsProblem = null;
    saving = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _settings.removeListener(_serverChanged);
    super.dispose();
  }
}
