import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/connection.dart';
import '../../core/ports.dart';
import 'settings_controller.dart';

/// Follows a [CompanionApi] beside the server in use: whether it is there ([available]) and what
/// it [serves]. Another server starts it afresh ([serverChanged]), Test connection asks again,
/// and an answer about a server no longer in use is dropped ([epoch]). A controller mixes it in
/// and calls [watch] once.
mixin CompanionWatch on ChangeNotifier {
  late final CompanionApi _companion;
  late final SettingsController _watched;

  /// The server in use, and where the companion was said to run beside it, as last seen.
  Connection? _server;
  Uri? _address;
  int _tests = 0;

  /// Counts the connection changes, so an answer from the server before is dropped.
  int epoch = 0;

  /// Whether the companion answers beside the server in use: null until it is asked.
  bool? available;
  Set<String> _features = const {};

  /// Whether the companion's `/health` names [feature].
  bool serves(String feature) => _features.contains(feature);

  /// Starts following [companion] beside the server [settings] has in use.
  void watch(CompanionApi companion, SettingsController settings) {
    _companion = companion;
    _watched = settings;
    _server = settings.connection;
    _address = settings.addressOf(companion.companion);
    _tests = settings.tests;
    settings.addListener(_settingsChanged);
    if (_server != null) unawaited(_detect());
  }

  /// Another server is in use, or the companion was said to run elsewhere: forget what was read
  /// from the one before. [available] and the features are cleared already, and listeners are
  /// told afterwards.
  @protected
  void serverChanged() {}

  /// What the companion answered changed: it was found, lost, or serves something else.
  @protected
  void detected() {}

  void _settingsChanged() {
    final here = _watched.connection;
    final address = _watched.addressOf(_companion.companion);
    if (here != _server || address != _address) {
      // The same server with the companion said to run elsewhere asks there afresh.
      final moved = here == _server;
      _server = here;
      _address = address;
      _tests = _watched.tests;
      epoch++;
      available = null;
      _features = const {};
      serverChanged();
      notifyListeners();
      if (here != null) unawaited(_detect(again: moved));
      return;
    }
    if (_watched.tests != _tests) {
      _tests = _watched.tests;
      if (here != null) unawaited(_detect(again: true));
    }
  }

  Future<void> _detect({bool again = false}) async {
    final asked = epoch;
    final found = await _companion.features(again: again);
    if (asked != epoch) return;
    final features = found ?? const <String>{};
    if (available == (found != null) && setEquals(features, _features)) return;
    available = found != null;
    _features = features;
    notifyListeners();
    detected();
  }

  /// Stops following the server in use.
  void unwatch() => _watched.removeListener(_settingsChanged);
}
