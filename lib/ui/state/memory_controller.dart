import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/memory.dart';
import '../../core/ports.dart';
import 'chat_controller.dart';
import 'follows_server.dart';
import 'notice.dart';
import 'read.dart';
import 'settings_controller.dart';

/// What the Memory page shows and changes for one workspace, [slug]: AnythingLLM's saved
/// memories, which every chat is shown, through the toolkit. Another server starts it afresh.
class MemoryController extends ChangeNotifier with FollowsServer {
  MemoryController(this._api, SettingsController settings, this._chat) {
    followServer(settings);
    _chat.addListener(_followed);
    _shown = slug;
  }

  final ToolkitApi _api;
  final ChatController _chat;

  /// The workspace picked on the page, or null for the open one.
  String? _picked;

  /// The workspace what is read describes.
  String? _shown;

  /// The workspace shown: the one picked, else the open one.
  String? get slug => _picked ?? _chat.activeSlug;

  /// The switches and the saved memories as last read, and why a read or a change failed.
  late final _memory = ReadSlot<(MemorySwitches, SavedMemories?)>(
    notifyListeners,
  );

  /// Whether saved memories are on, and saved from chats; null before they are read.
  MemorySwitches? get switches => _memory.value?.$1;

  /// The saved memories, or null before they are read or while they are off.
  SavedMemories? get saved => _memory.value?.$2;

  bool get loading => _memory.loading;

  /// Whether a change is being sent.
  bool busy = false;

  Notice? get savedProblem => _memory.problem;

  @override
  void serverChanged(_) {
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
    _memory.reset();
    busy = false;
    notifyListeners();
  }

  /// Shows workspace [slug]'s memory.
  void show(String slug) {
    if (slug == this.slug) return;
    _picked = slug;
    _reset();
  }

  /// Reads the memory after the frame, unless it is read already, or the last read failed
  /// (Refresh asks again).
  void want() {
    if (_memory.asked || slug == null || server == null) return;
    afterFrame(() {
      if (switches == null && !loading) unawaited(read());
    });
  }

  /// Reads the saved memories of the workspace shown again.
  Future<void> read() async {
    final slug = this.slug;
    if (slug == null || server == null) return;
    await _memory.read(() async {
      final on = await _api.memorySwitches();
      return (on, on.enabled ? await _api.savedMemories(slug) : null);
    }, failTitle: 'Could not read the saved memories');
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
    final at = here;
    final slug = this.slug;
    if (slug == null || busy) return false;
    return changeThenRead(
      title,
      () => call(slug),
      current: () => at.current && slug == this.slug,
      busy: (on) {
        busy = on;
        notifyListeners();
      },
      readAgain: (failed) async {
        await read();
        if (failed != null) {
          _memory.problem = failed;
          notifyListeners();
        }
      },
    );
  }

  @override
  void dispose() {
    _chat.removeListener(_followed);
    super.dispose();
  }
}
