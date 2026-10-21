import 'package:flutter/foundation.dart';

import '../../core/ports.dart';
import '../../core/prefs.dart';
import '../../core/shortcuts.dart';
import 'notice.dart';

/// The app's preferences: read once at start, written on every change.
class PrefsController extends ChangeNotifier {
  PrefsController(this._store);

  final PrefsStore _store;

  Prefs prefs = const Prefs();

  /// Why the last change could not be saved. The change still holds for this run.
  Notice? problem;

  /// The address of the server in use, which the switched-off documents and the last chat
  /// belong to, or null when none is.
  String? _server;

  Future<void> load() async {
    prefs = await _store.load();
    notifyListeners();
    await _adopt();
  }

  /// Makes [server] the one the switched-off documents and the last chat are about. What was
  /// saved before servers were told apart becomes the first server's.
  Future<void> useServer(String? server) async {
    _server = server;
    await _adopt();
  }

  Future<void> _adopt() async {
    if (_server case final server? when prefs.hasUnowned) {
      await _change(prefs.adoptedBy(server));
    }
  }

  /// The documents switched off in workspace [slug] of the server in use.
  List<OffDoc> offIn(String slug) =>
      _server == null ? const [] : prefs.offIn(_server!, slug);

  Future<void> setOff(String slug, List<OffDoc> docs) async {
    if (_server case final server?) {
      await _change(prefs.withOff(server, slug, docs));
    }
  }

  /// Arranges the workspaces as [slugs].
  Future<void> setWorkspaceOrder(List<String> slugs) =>
      _change(prefs.withOrder(slugs));

  /// Notes that this device used chat [thread] of workspace [slug] now, for Recent.
  Future<void> useChat(String slug, String thread) async {
    final server = _server;
    // Already the last used, as when its answer ends while it is on screen: nothing to write.
    if (server != null && prefs.recentIn(server, slug).firstOrNull != thread) {
      await _change(prefs.withUse(server, slug, thread));
    }
  }

  /// Notes the chat on screen in one write: chat [thread] of workspace [slug] as the last chat
  /// and, when it is no draft, the last used, as a chat opened is.
  Future<void> showChat(String slug, String? thread) async {
    final server = _server;
    if (server == null || prefs.lastChat == LastChat(slug, thread, server)) {
      return;
    }
    var next = prefs.withLastChat(server, slug, thread);
    if (thread != null) next = next.withUse(server, slug, thread);
    await _change(next);
  }

  /// The chats pinned in workspace [slug] of the server in use.
  List<String> pinnedIn(String slug) =>
      _server == null ? const [] : prefs.pinnedIn(_server!, slug);

  /// The chats this device used last in workspace [slug] of the server in use, last used
  /// first.
  List<String> recentIn(String slug) =>
      _server == null ? const [] : prefs.recentIn(_server!, slug);

  Future<void> setPinned(String slug, String thread, {required bool on}) async {
    if (_server case final server?) {
      await _change(prefs.withPin(server, slug, thread, on: on));
    }
  }

  /// Forgets a deleted chat's pin and when it was used.
  Future<void> forgetChat(String slug, String thread) async {
    final server = _server;
    if (server != null && prefs.keepsChat(server, slug, thread)) {
      await _change(prefs.withoutChat(server, slug, thread));
    }
  }

  /// Drops a deleted workspace from the arrangement, the last chat, and what is kept of its
  /// chats and switched-off documents.
  Future<void> forgetWorkspace(String slug) async {
    if (_server case final server?) {
      await _changeIfNew(prefs.withoutWorkspace(server, slug));
    }
  }

  /// Keeps what is kept of a workspace, its order, switched-off files, last chat, chats,
  /// shortcuts and their uses, when its slug changes.
  Future<void> renameWorkspace(String from, String to) async {
    if (_server case final server?) {
      await _changeIfNew(prefs.withRenamedWorkspace(server, from, to));
    }
  }

  Future<void> setTheme(ThemePref theme) => _change(prefs.withTheme(theme));

  Future<void> setTextSize(TextSize size) => _change(prefs.withTextSize(size));

  Future<void> setSwitch(ChatSwitch which, bool on) =>
      _change(prefs.withSwitch(which, on));

  /// The built-in and user-made shortcuts available in workspace [slug].
  List<PromptShortcut> shortcutsIn(String? slug) {
    final server = _server;
    if (server == null || slug == null) return const [];
    final key = Prefs.offKey(server, slug);
    return [
      ...builtInPromptShortcuts,
      ...prefs.shortcuts,
    ].where((shortcut) => shortcut.appliesTo(key)).toList();
  }

  /// Whether [name] is free among the built-in and user-made shortcuts.
  bool shortcutNameAvailable(String name, {String? exceptId}) =>
      validShortcutName(name) &&
      ![
        ...builtInPromptShortcuts,
        ...prefs.shortcuts.where((shortcut) => shortcut.id != exceptId),
      ].any((shortcut) => shortcut.name == name);

  Future<void> saveShortcut(PromptShortcut shortcut) => _change(
    prefs.withShortcuts([
      ...prefs.shortcuts.where((item) => item.id != shortcut.id),
      shortcut,
    ]),
  );

  Future<void> deleteShortcut(String id) => _change(
    prefs.withShortcuts(
      prefs.shortcuts.where((shortcut) => shortcut.id != id).toList(),
    ),
  );

  /// Remembers how a local shortcut labelled an exchange on this device.
  Future<void> rememberShortcutUse(
    String slug,
    String thread,
    int chatId,
    ShortcutUse use,
  ) async {
    final server = _server;
    if (server == null) return;
    final key = Prefs.shortcutUseKey(server, slug, thread, chatId);
    await _change(prefs.withShortcutUse(key, use));
  }

  /// The shortcut label and detail saved for this exchange, if any.
  ShortcutUse? shortcutUse(String slug, String thread, int chatId) {
    final server = _server;
    return server == null || prefs.shortcutUses.isEmpty
        ? null
        : prefs.shortcutUses[Prefs.shortcutUseKey(
            server,
            slug,
            thread,
            chatId,
          )];
  }

  /// [_change]s to [next] unless it holds what the prefs hold already, so nothing is written.
  Future<void> _changeIfNew(Prefs next) async {
    if (next.encode() != prefs.encode()) await _change(next);
  }

  Future<void> _change(Prefs next) async {
    prefs = next;
    notifyListeners();
    final before = problem;
    try {
      await _store.save(next);
      problem = null;
    } on ApiException catch (error) {
      problem = Notice('Could not save your preferences', error.message);
    }
    if (problem != before) notifyListeners();
  }
}
