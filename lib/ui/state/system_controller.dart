import 'package:flutter/foundation.dart';

import '../../core/connection.dart';
import '../../core/embeds.dart';
import '../../core/ports.dart';
import '../../core/system_settings.dart';
import 'notice.dart';
import 'settings_controller.dart';

/// The server itself, apart from its workspaces: its settings, how many vectors its database
/// holds, and its chat embeds. A new server starts it afresh.
class SystemController extends ChangeNotifier {
  SystemController(this._api, this._settings)
    : _server = _settings.connection?.withPassword(null) {
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

  /// The server's settings, with every secret replaced by whether it is set, or null until read.
  Map<String, Object?>? settings;

  /// Why the last read or save of the settings failed.
  Notice? settingsProblem;

  /// Whether the settings are being saved.
  bool saving = false;

  /// Whether the settings show as JSON rather than as the form. It holds through a save.
  bool settingsAsJson = false;

  /// Counts each time [settings] is read afresh, so a form knows to drop its draft.
  int settingsRevision = 0;

  /// Reads the server's settings.
  Future<void> readSettings() async {
    final server = _server;
    if (server == null) return;
    try {
      final read = await _api.systemSettings();
      if (_server != server) return;
      settings = read;
      settingsProblem = null;
    } on ApiException catch (error) {
      if (_server != server) return;
      settingsProblem = Notice('Could not read the settings', error.message);
    }
    settingsRevision++;
    notifyListeners();
  }

  void showSettingsAsJson(bool json) {
    if (settingsAsJson == json) return;
    settingsAsJson = json;
    notifyListeners();
  }

  /// The settings in [draft] whose change makes the server delete every vector, or none when the
  /// draft cannot be read.
  List<String> vectorResets(String draft) {
    final was = settings;
    if (was == null) return const [];
    try {
      return [
        for (final key in parseSystemSettings(draft, was).keys)
          if (resetsVectors.contains(key)) key,
      ];
    } on ApiException {
      return const [];
    }
  }

  /// Writes the settings in [draft] that changed, then reads them again whether that worked or
  /// not, since the server may have written some before it refused one. Returns whether all were
  /// written; why not shows as [settingsProblem].
  Future<bool> saveSettings(String draft) async {
    final server = _server;
    final was = settings;
    if (server == null || was == null || saving) return false;
    final Map<String, String> changes;
    try {
      changes = parseSystemSettings(draft, was);
    } on ApiException catch (error) {
      settingsProblem = Notice('Could not save the settings', error.message);
      notifyListeners();
      return false;
    }
    if (changes.isEmpty) return true;
    saving = true;
    notifyListeners();
    Notice? failed;
    try {
      await _api.updateSystem(changes);
    } on ApiException catch (error) {
      failed = Notice('Could not save the settings', error.message);
    }
    try {
      final read = await _api.systemSettings();
      if (_server == server) settings = read;
    } on ApiException catch (error) {
      failed ??= Notice('Could not read the settings again', error.message);
    }
    if (_server != server) return false;
    saving = false;
    settingsProblem = failed;
    settingsRevision++;
    notifyListeners();
    return failed == null;
  }

  /// Why the last read of the vectors failed.
  Notice? problem;

  /// The server's chat embeds, or null until read.
  List<Embed>? embeds;

  /// Why the last read or change of an embed failed.
  Notice? embedProblem;

  /// Whether an embed is being made, changed or deleted.
  bool changing = false;

  /// Reads the server's chat embeds.
  Future<void> readEmbeds() =>
      _embedCall('Could not read the embeds', () async {});

  /// Makes [embed], and returns whether it was made.
  Future<bool> createEmbed(NewEmbed embed) =>
      _embedCall('Could not make the embed', () => _api.createEmbed(embed));

  /// Turns embed [uuid] on or off.
  Future<bool> setEnabled(String uuid, bool enabled) => _embedCall(
    'Could not change the embed',
    () => _api.updateEmbed(uuid, enabled: enabled),
  );

  /// Sets the mode embed [uuid] answers in.
  Future<bool> setMode(String uuid, EmbedMode mode) => _embedCall(
    'Could not change the embed',
    () => _api.updateEmbed(uuid, mode: mode),
  );

  Future<bool> deleteEmbed(String uuid) =>
      _embedCall('Could not delete the embed', () => _api.deleteEmbed(uuid));

  /// The chats embed [uuid] has held, or null when they could not be read, and why shows as
  /// [embedProblem].
  Future<List<EmbedChat>?> embedChats(String uuid) async {
    final server = _server;
    try {
      return await _api.embedChats(uuid);
    } on ApiException catch (error) {
      if (_server == server) {
        embedProblem = Notice(
          'Could not read the embed\'s chats',
          error.message,
        );
        notifyListeners();
      }
      return null;
    }
  }

  /// Runs [change], then reads the embeds again whether it worked or not. Returns whether it
  /// worked; a failure shows as [embedProblem], titled [failTitle].
  Future<bool> _embedCall(
    String failTitle,
    Future<void> Function() change,
  ) async {
    final server = _server;
    if (server == null || changing) return false;
    changing = true;
    notifyListeners();
    Notice? failed;
    try {
      await change();
    } on ApiException catch (error) {
      failed = Notice(failTitle, error.message);
    }
    try {
      final read = await _api.embeds();
      if (_server == server) embeds = read;
    } on ApiException catch (error) {
      failed ??= Notice('Could not read the embeds', error.message);
    }
    if (_server != server) return false;
    changing = false;
    embedProblem = failed;
    notifyListeners();
    return failed == null;
  }

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
    // A password saved or forgotten is the same server.
    final now = _settings.connection?.withPassword(null);
    if (now == _server) return;
    _server = now;
    vectors = null;
    vectorDb = null;
    problem = null;
    settings = null;
    settingsProblem = null;
    saving = false;
    embeds = null;
    embedProblem = null;
    changing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _settings.removeListener(_serverChanged);
    super.dispose();
  }
}
