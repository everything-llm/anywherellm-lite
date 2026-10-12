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
/// memories, which every chat is shown. Another server, or another password, starts it afresh.
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

  bool loading = false;

  /// Whether a change is being sent.
  bool busy = false;

  Notice? savedProblem;

  int _reads = 0;

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
    switches = null;
    saved = null;
    loading = false;
    busy = false;
    savedProblem = null;
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
    if (switches != null || loading || savedProblem != null) return;
    if (slug == null || _server == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (switches == null && !loading) unawaited(read());
    });
  }

  /// Reads the saved memories of the workspace shown again.
  Future<void> read() async {
    final slug = this.slug;
    if (slug == null || _server == null) return;
    final number = ++_reads;
    loading = true;
    notifyListeners();
    try {
      final on = await _api.memorySwitches();
      final listed = on.enabled ? await _api.savedMemories(slug) : null;
      if (number != _reads) return;
      switches = on;
      saved = listed;
      savedProblem = null;
    } on ApiException catch (error) {
      if (number != _reads) return;
      savedProblem = Notice('Could not read the saved memories', error.message);
    }
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

  /// Sends [call] for the workspace shown, then reads what the server has now, whether it went
  /// or not, and shows why it failed over the saved memories. Whether it went.
  Future<bool> _change(
    String title,
    Future<void> Function(String slug) call,
  ) async {
    final server = _server;
    final slug = this.slug;
    if (slug == null || busy) return false;
    busy = true;
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
    if (failed != null) {
      savedProblem = failed;
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
