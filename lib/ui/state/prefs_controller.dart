import 'package:flutter/foundation.dart';

import '../../core/ports.dart';
import '../../core/prefs.dart';
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

  /// Drops a deleted workspace from the arrangement and the last chat.
  Future<void> forgetWorkspace(String slug) async {
    final server = _server;
    if (server == null) return;
    if (prefs.workspaceOrder.contains(slug) ||
        prefs.lastChatIn(server, slug) ||
        prefs.keepsChatsOf(server, slug)) {
      await _change(prefs.withoutWorkspace(server, slug));
    }
  }

  /// Keeps a workspace's order, switched-off files and last chat when its slug changes.
  Future<void> renameWorkspace(String from, String to) async {
    final server = _server;
    if (server == null) return;
    if (prefs.workspaceOrder.contains(from) ||
        prefs.switchedOff.containsKey(Prefs.offKey(server, from)) ||
        prefs.keepsChatsOf(server, from) ||
        prefs.lastChatIn(server, from)) {
      await _change(prefs.withRenamedWorkspace(server, from, to));
    }
  }

  Future<void> setTheme(ThemePref theme) => _change(prefs.withTheme(theme));

  Future<void> setTextSize(TextSize size) => _change(prefs.withTextSize(size));

  Future<void> setSwitch(ChatSwitch which, bool on) =>
      _change(prefs.withSwitch(which, on));

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
