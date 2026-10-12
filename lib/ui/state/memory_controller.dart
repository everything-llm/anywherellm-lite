import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../core/connection.dart';
import '../../core/memory.dart';
import '../../core/ports.dart';
import 'chat_controller.dart';
import 'notice.dart';
import 'settings_controller.dart';

/// What the Memory page shows and changes for one workspace, [slug]: AnythingLLM's saved
/// memories, which every chat is shown, and the everythingllm host's long-term memory, which the
/// agent recalls from. Another server, or another password, starts it afresh. A server without
/// the host's route leaves [longUnavailable] set.
class MemoryController extends ChangeNotifier {
  MemoryController(this._api, this._settings, this._chat) {
    _settings.addListener(_changed);
    _chat.addListener(_followed);
    _server = _settings.connection;
    _shown = slug;
  }

  final AnythingLlmApi _api;
  final SettingsController _settings;
  final ChatController _chat;

  /// The server read, with its password, which the saved memories sign in with.
  Connection? _server;

  /// The workspace picked on the page, or null for the open one.
  String? _picked;

  /// The workspace what is read describes.
  String? _shown;

  /// The workspace shown: the one picked, else the open one.
  String? get slug => _picked ?? _chat.activeSlug;

  /// Whether saved memories are on, and saved from chats; null before they are read.
  MemorySwitches? switches;

  /// The saved memories, or null before they are read or while they are off.
  SavedMemories? saved;

  /// The long-term memory, or null before it is read.
  LongMemory? long;

  /// Whether the server has no long-term memory route.
  bool longUnavailable = false;

  bool loading = false;

  /// Whether a change is being sent.
  bool busy = false;

  Notice? savedProblem;
  Notice? longProblem;

  /// What the last Remember did not keep, because a fact already said it.
  String? longNote;

  /// What the search asked, and what it found, closest first; null while nothing is asked.
  String query = '';
  List<RecallHit>? hits;
  bool recalling = false;

  int _reads = 0;
  int _recalls = 0;

  void _changed() {
    final here = _settings.connection;
    if (here == _server) return;
    _server = here;
    _picked = null;
    _reset();
  }

  /// A workspace opened elsewhere shows here too, unless the page picked one.
  void _followed() {
    if (slug == _shown) return;
    _reset();
  }

  void _reset() {
    _shown = slug;
    _reads++;
    _recalls++;
    switches = null;
    saved = null;
    long = null;
    longUnavailable = false;
    loading = false;
    busy = false;
    savedProblem = null;
    longProblem = null;
    longNote = null;
    query = '';
    hits = null;
    recalling = false;
    notifyListeners();
  }

  /// Shows workspace [slug]'s memory.
  void show(String slug) {
    if (slug == this.slug) return;
    _picked = slug;
    _reset();
  }

  /// Reads the memory unless it is read already, or the last read failed (Refresh asks again).
  /// It asks after the frame, since a read tells the listeners at once, so a build may call it.
  void want() {
    if (switches != null || long != null || longUnavailable || loading) return;
    if (savedProblem != null || longProblem != null) return;
    if (slug == null || _server == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (switches == null && long == null && !loading) unawaited(read());
    });
  }

  /// Reads both memories of the workspace shown again.
  Future<void> read() async {
    final slug = this.slug;
    if (slug == null || _server == null) return;
    final number = ++_reads;
    loading = true;
    notifyListeners();
    Future<void> readSaved() async {
      try {
        final on = await _api.memorySwitches();
        final listed = on.enabled ? await _api.savedMemories(slug) : null;
        if (number != _reads) return;
        switches = on;
        saved = listed;
        savedProblem = null;
      } on ApiException catch (error) {
        if (number != _reads) return;
        savedProblem = Notice(
          'Could not read the saved memories',
          error.message,
        );
      }
    }

    Future<void> readLong() async {
      try {
        final read = await _api.longMemory(slug);
        if (number != _reads) return;
        long = read;
        longUnavailable = read == null;
        longProblem = null;
      } on ApiException catch (error) {
        if (number != _reads) return;
        longProblem = Notice(
          'Could not read the long-term memory',
          error.message,
        );
      }
    }

    await Future.wait([readSaved(), readLong()]);
    if (number != _reads) return;
    loading = false;
    notifyListeners();
  }

  /// Turns saved memories, or saving them from chats, on or off.
  Future<bool> setSwitches({bool? enabled, bool? learn}) => _change(
    'Could not change saved memories',
    (_) => _api.setMemorySwitches(enabled: enabled, learn: learn),
  );

  /// Saves [text] for every workspace when [global], else for the one shown.
  Future<bool> add(String text, {required bool global}) => _change(
    'Could not save the memory',
    (slug) => _api.addMemory(slug, text, global: global),
  );

  /// Changes [memory]'s text to [text], and moves it to every workspace or this one alone.
  Future<bool> edit(SavedMemory memory, String text, {required bool global}) =>
      _change('Could not change the memory', (slug) async {
        if (text != memory.text) await _api.editMemory(memory.id, text);
        if (global != memory.global) {
          await _api.moveMemory(memory.id, toWorkspace: global ? null : slug);
        }
      });

  Future<bool> delete(SavedMemory memory) => _change(
    'Could not delete the memory',
    (_) => _api.deleteMemory(memory.id),
  );

  /// Keeps [text] in the long-term memory, for every workspace when [global].
  Future<bool> remember(String text, {required bool global}) =>
      _change('Could not remember it', (slug) async {
        final kept = await _api.rememberLong(slug, text, global: global);
        if (!kept.isNew) longNote = 'Already kept: ${kept.fact.text}';
      }, long: true);

  Future<bool> forgetFact(LongFact fact) => _change(
    'Could not forget the fact',
    (slug) => _api.forgetLong(slug, fact: fact.id),
    long: true,
  );

  /// Forgets the text read in from [path]; the file stays.
  Future<bool> forgetFile(String path) => _change(
    'Could not forget the file\'s text',
    (slug) => _api.forgetLong(slug, path: path),
    long: true,
  );

  /// Finds the facts and parts of files closest to [query]; an empty one clears the search.
  Future<void> recall(String query) async {
    final slug = this.slug;
    this.query = query.trim();
    final number = ++_recalls;
    if (slug == null || this.query.isEmpty) {
      hits = null;
      recalling = false;
      notifyListeners();
      return;
    }
    recalling = true;
    notifyListeners();
    try {
      final found = await _api.recallMemory(slug, this.query);
      if (number != _recalls) return;
      hits = found;
      longProblem = null;
    } on ApiException catch (error) {
      if (number != _recalls) return;
      hits = null;
      longProblem = Notice(
        'Could not search the long-term memory',
        error.message,
      );
    }
    recalling = false;
    notifyListeners();
  }

  /// Sends [call] for the workspace shown, then reads what the server has now, whether it went
  /// or not, and shows why it failed under the saved memories, or the long-term ones when
  /// [long]. Whether it went.
  Future<bool> _change(
    String title,
    Future<void> Function(String slug) call, {
    bool long = false,
  }) async {
    final server = _server;
    final slug = this.slug;
    if (slug == null || busy) return false;
    busy = true;
    longNote = null;
    notifyListeners();
    Notice? failed;
    try {
      await call(slug);
    } on ApiException catch (error) {
      failed = Notice(title, error.message);
    }
    if (server != _server || slug != this.slug) return false;
    busy = false;
    await read();
    if (long && query.isNotEmpty) await recall(query);
    if (failed != null) {
      if (long) {
        longProblem = failed;
      } else {
        savedProblem = failed;
      }
      notifyListeners();
    }
    return failed == null;
  }

  @override
  void dispose() {
    _settings.removeListener(_changed);
    _chat.removeListener(_followed);
    super.dispose();
  }
}
