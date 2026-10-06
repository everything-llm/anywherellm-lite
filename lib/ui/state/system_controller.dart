import 'package:flutter/foundation.dart';

import '../../core/connection.dart';
import '../../core/ports.dart';
import 'notice.dart';
import 'settings_controller.dart';

/// The server itself, apart from its workspaces: how many vectors its database holds. A new
/// server starts it afresh.
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

  /// The vector database the server uses, or null until read or when it does not say.
  String? vectorDb;

  /// Why the last read failed.
  Notice? problem;

  /// Reads how many vectors the server holds, and in which database.
  Future<void> readVectors() async {
    final server = _server;
    if (server == null) return;
    try {
      final count = await _api.vectorCount();
      final settings = await _api.systemSettings();
      if (_server != server) return;
      vectors = count;
      vectorDb = switch (settings['VectorDB']) {
        final String db when db.isNotEmpty => db,
        _ => null,
      };
      problem = null;
    } on ApiException catch (error) {
      if (_server != server) return;
      problem = Notice('Could not count the vectors', error.message);
    }
    notifyListeners();
  }

  void _serverChanged() {
    if (_settings.connection == _server) return;
    _server = _settings.connection;
    vectors = null;
    vectorDb = null;
    problem = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _settings.removeListener(_serverChanged);
    super.dispose();
  }
}
