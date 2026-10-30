import 'package:flutter/foundation.dart';

import '../../core/ports.dart';
import '../../core/prefs.dart';
import '../../core/server_models.dart';
import '../../core/shortcuts.dart';
import '../../core/users.dart';
import 'notice.dart';

/// The app's preferences: read once at start, written on every change.
class PrefsController extends ChangeNotifier {
  PrefsController(this._store);

  final PrefsStore _store;

  Prefs prefs = const Prefs();

  /// Why the last change could not be saved. The change still holds for this run.
  Notice? problem;

  /// The address of the server in use, which the pins, recent chats, last folder and the last
  /// chat belong to, or null when none is.
  String? _server;

  Future<void> load() async {
    prefs = await _store.load();
    notifyListeners();
    await _adopt();
  }

  /// Makes [server] the one the pins, recent chats, last folder and the last chat are about.
  /// What was saved before servers were told apart becomes the first server's.
  Future<void> useServer(String? server) async {
    _server = server;
    await _adopt();
  }

  Future<void> _adopt() async {
    if (_server case final server? when prefs.hasUnowned) {
      await _change(prefs.adoptedBy(server));
    }
  }

  /// The library folder of the server in use that a document was last moved into, or null.
  String? get lastFolder =>
      _server == null ? null : prefs.lastFolders[_server!];

  /// Makes [folder] the one a new document goes into on the server in use.
  Future<void> setLastFolder(String folder) async {
    if (_server case final server? when prefs.lastFolders[server] != folder) {
      await _change(prefs.withLastFolder(server, folder));
    }
  }

  /// Whom chats on the server in use are saved as, or null while no one is chosen there or no
  /// server is in use.
  ServerUser? get chosenUser => _server == null ? null : prefs.userOn(_server!);

  /// Saves chats on the server in use as [user] from now on.
  Future<void> chooseUser(ServerUser user) async {
    if (_server case final server? when prefs.userOn(server) != user) {
      await _change(prefs.withUser(server, user));
    }
  }

  /// Arranges the workspaces as [slugs].
  Future<void> setWorkspaceOrder(List<String> slugs) =>
      _change(prefs.withOrder(slugs));

  /// Notes that this device used chat [thread] of workspace [slug] now, for Recent. Main chat,
  /// always first in the list, is never Recent, so it takes no thread's place there.
  Future<void> useChat(String slug, String thread) async {
    final server = _server;
    // Already the last used, as when its answer ends while it is on screen: nothing to write.
    if (server != null &&
        !isMainChat(thread) &&
        prefs.recentIn(server, slug).firstOrNull != thread) {
      await _change(prefs.withUse(server, slug, thread));
    }
  }

  /// Notes the chat on screen in one write: chat [thread] of workspace [slug] as the last chat
  /// and, when it is a thread, the last used, as a chat opened is.
  Future<void> showChat(String slug, String? thread) async {
    final server = _server;
    if (server == null || prefs.lastChat == LastChat(slug, thread, server)) {
      return;
    }
    var next = prefs.withLastChat(server, slug, thread);
    if (thread != null && !isMainChat(thread)) {
      next = next.withUse(server, slug, thread);
    }
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

  /// The messages kept waiting in chat [thread] of workspace [slug] of the server in use.
  List<SavedOnDeck> onDeckIn(String slug, String thread) =>
      _server == null ? const [] : prefs.onDeckIn(_server!, slug, thread);

  /// Keeps [messages] as the ones waiting in chat [thread] of workspace [slug], so they survive
  /// the app closing.
  Future<void> setOnDeck(
    String slug,
    String thread,
    List<SavedOnDeck> messages,
  ) async {
    final server = _server;
    if (server == null ||
        (messages.isEmpty && prefs.onDeckIn(server, slug, thread).isEmpty)) {
      return;
    }
    await _change(prefs.withOnDeck(server, slug, thread, messages));
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
      ].any((shortcut) => shortcut.answersTo(name));

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
