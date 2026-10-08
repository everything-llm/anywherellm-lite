import 'package:flutter/foundation.dart';

import '../../core/chat_log.dart';
import '../../core/connection.dart';
import '../../core/embeds.dart';
import '../../core/ports.dart';
import '../../core/server_models.dart';
import '../../core/system_settings.dart';
import 'notice.dart';
import 'settings_controller.dart';

/// The server itself, apart from its workspaces: its settings, how many vectors its database
/// holds, its chat embeds and the chats it recorded. A new server starts it afresh.
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

  /// The server's settings, with every secret replaced by whether it is set, or null until read.
  Map<String, Object?>? settings;

  /// Why the last read or save of the settings failed.
  Notice? settingsProblem;

  /// Whether the settings are being saved.
  bool saving = false;

  /// Counts each time [settings] is read afresh, so a form knows to drop its draft.
  int settingsRevision = 0;

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
    settingsRevision++;
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
    // The server may have written some before it refused one, so a reset may have run either way.
    if (_server == server && changes.keys.any(resetsVectors.contains)) {
      vectors = null;
    }
    final number = ++_settingsReads;
    try {
      final read = await _api.systemSettings();
      if (_server == server && number == _settingsReads) settings = read;
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
      final chats = await _api.embedChats(uuid);
      if (_server == server && embedProblem != null) {
        embedProblem = null;
        notifyListeners();
      }
      return chats;
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

  /// Reads how many vectors the server holds.
  Future<void> readVectors() async {
    final server = _server;
    if (server == null) return;
    try {
      final count = await _api.vectorCount();
      if (_server != server) return;
      vectors = count;
      problem = null;
    } on ApiException catch (error) {
      if (_server != server) return;
      problem = Notice('Could not count the vectors', error.message);
    }
    notifyListeners();
  }

  /// The chats the server recorded, newest first, as far as they have been read, or null until
  /// read.
  List<LoggedChat>? chats;

  /// Whether the server has more chats than [chats].
  bool chatsMore = false;

  /// Whether a page of chats is being read.
  bool readingChats = false;

  /// Why the last read of the chats failed.
  Notice? chatsProblem;

  /// Whether the chats are being exported.
  bool exporting = false;

  /// Why the last export failed.
  Notice? exportProblem;

  /// Reads the newest page of the server's chats.
  Future<void> readChats() => _readChats(0);

  /// Reads the page of chats after those in [chats].
  Future<void> moreChats() =>
      _readChats((chats?.length ?? 0) ~/ ChatLog.pageSize);

  Future<void> _readChats(int page) async {
    final server = _server;
    if (server == null || readingChats) return;
    readingChats = true;
    notifyListeners();
    try {
      final log = await _api.workspaceChats(page: page);
      if (_server != server) return;
      chats = [if (page > 0) ...?chats, ...log.chats];
      chatsMore = log.more;
      chatsProblem = null;
    } on ApiException catch (error) {
      if (_server != server) return;
      chatsProblem = Notice('Could not read the chats', error.message);
    }
    readingChats = false;
    notifyListeners();
  }

  /// Every chat on the server in [format], or null when the server would not give them, which
  /// [exportProblem] then says.
  Future<List<int>?> exportChats(ChatExport format) async {
    final server = _server;
    if (server == null) return null;
    exporting = true;
    exportProblem = null;
    notifyListeners();
    List<int>? bytes;
    try {
      bytes = await _api.exportChats(format);
    } on ApiException catch (error) {
      if (_server == server) {
        exportProblem = Notice('Could not export the chats', error.message);
      }
    }
    if (_server != server) return null;
    exporting = false;
    notifyListeners();
    return bytes;
  }

  /// Shows why saving an export failed.
  void reportExport(String title, String text) {
    exportProblem = Notice(title, text);
    notifyListeners();
  }

  void _serverChanged() {
    // A password saved or forgotten is the same server.
    final now = _settings.connection?.withPassword(null);
    if (now == _server) return;
    _server = now;
    _reading = null;
    vectors = null;
    problem = null;
    settings = null;
    settingsProblem = null;
    saving = false;
    embeds = null;
    embedProblem = null;
    changing = false;
    chats = null;
    chatsMore = false;
    readingChats = false;
    chatsProblem = null;
    exporting = false;
    exportProblem = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _settings.removeListener(_serverChanged);
    super.dispose();
  }
}
