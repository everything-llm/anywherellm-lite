import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/chat.dart';
import '../../core/commands.dart';
import '../../core/connection.dart';
import '../../core/ports.dart';
import '../../core/server_models.dart';
import 'notice.dart';
import 'prefs_controller.dart';
import 'settings_controller.dart';

/// One turn on screen. An answer grows while it streams, and notifies only its own listeners
/// as it does, so a chunk rebuilds the answer and nothing else.
class Turn extends ChangeNotifier {
  Turn.user(this.text, {this.attachments = const []})
    : role = Role.user,
      streaming = false;

  Turn.answer() : role = Role.assistant, text = '', streaming = true;

  Turn.saved(ChatMessage message)
    : role = message.role,
      text = message.text,
      citations = message.citations,
      attachments = message.attachments,
      streaming = false;

  final Role role;
  String text;

  /// The names of the files sent with a question.
  List<String> attachments = const [];
  List<Citation> citations = const [];
  bool streaming;

  /// Why the answer failed, or null.
  String? error;

  /// What an agent is doing while the answer runs, such as a tool it runs, or null.
  String? status;

  void _grow(String more) {
    text += more;
    notifyListeners();
  }

  void _setStatus(String line) {
    status = line;
    notifyListeners();
  }

  void _replace(String whole) {
    text = whole;
    notifyListeners();
  }
}

/// The one answer running: the chat it belongs to, null while its draft's thread is being made,
/// and the stream it reads.
class _Running {
  _Running(this.answer, this.slug);

  final Turn answer;

  /// The workspace the answer runs in.
  final String slug;
  String? thread;
  StreamSubscription<ChatEvent>? stream;
}

/// The workspaces and their chats, the chat on screen, and the one answer that may be running.
///
/// A chat not yet asked anything is a draft: it lives only here until its first message, which
/// makes the thread on the server. Everything it knows is about the server in [_settings]; a new
/// server starts it afresh.
class ChatController extends ChangeNotifier {
  ChatController(this._api, this._settings, this._prefs)
    : _server = _settings.connection {
    _settings.addListener(_serverChanged);
  }

  final AnythingLlmApi _api;
  final SettingsController _settings;
  final PrefsController _prefs;

  /// The connection the fields below describe.
  Connection? _server;

  List<Workspace> workspaces = const [];

  /// Each workspace's chats, newest last, by workspace slug.
  final Map<String, List<Thread>> _threads = {};

  /// How many documents each workspace holds, for the ones read so far.
  final Map<String, int> docCounts = {};

  String? activeSlug;

  /// The chat on screen, or null for a draft.
  String? activeThread;

  final Map<String, List<Turn>> _turns = {};
  final List<Turn> _draft = [];

  /// The chats whose names the person chose, which the first message does not rename.
  final Set<String> _named = {};

  /// The server's slash-command presets, or none when they cannot be read.
  List<SlashCommand> _presets = const [];

  /// The commands a message can start with: `/reset`, then the server's presets.
  List<SlashCommand> get commands => withBuiltIns(_presets);

  /// The answer running. Only one runs at a time.
  _Running? _running;

  bool loading = false;

  /// Why the last load or change failed.
  Notice? problem;

  /// Why a link in an answer did not open. It clears after [linkNoticeFor], or on the next
  /// message or chat opened.
  Notice? linkNotice;

  Timer? _linkTimer;

  static const linkNoticeFor = Duration(seconds: 6);

  Workspace? get active =>
      workspaces.where((w) => w.slug == activeSlug).firstOrNull;

  List<Thread> threadsOf(String slug) => _threads[slug] ?? const [];

  Thread? get thread => activeSlug == null
      ? null
      : threadsOf(activeSlug!).where((t) => t.slug == activeThread).firstOrNull;

  String get title => thread?.name ?? newChatName;

  List<Turn> get turns =>
      activeThread == null ? _draft : (_turns[activeThread] ?? const []);

  bool get busy => _running != null;

  /// Whether the chat on screen can take a message: a draft, or a chat whose history is read.
  bool get ready => activeThread == null || _turns.containsKey(activeThread);

  /// Whether the chat on screen is the one answering.
  bool get answeringHere => busy && turns.contains(_running!.answer);

  bool isAnswering(String thread) => _running?.thread == thread;

  bool answeringIn(String slug) => _running?.slug == slug;

  @override
  void dispose() {
    _settings.removeListener(_serverChanged);
    _running?.stream?.cancel();
    _linkTimer?.cancel();
    super.dispose();
  }

  void _serverChanged() {
    if (_settings.connection == _server) return;
    _server = _settings.connection;
    _running?.stream?.cancel();
    _running = null;
    workspaces = const [];
    _threads.clear();
    _turns.clear();
    _draft.clear();
    docCounts.clear();
    _presets = const [];
    activeSlug = null;
    activeThread = null;
    problem = null;
    _clearLinkNotice();
    notifyListeners();
    if (_server != null) unawaited(load());
  }

  /// Reads the workspaces and their chats, keeping the one on screen when it still exists.
  Future<void> load() async {
    if (_server == null) return;
    loading = true;
    notifyListeners();
    await _try('Could not read the workspaces', () async {
      workspaces = await _api.workspaces();
      _threads
        ..clear()
        ..addAll({
          for (final w in workspaces) w.slug: [...w.threads],
        });
    });
    loading = false;
    if (active == null) {
      await select(workspaces.firstOrNull?.slug);
    } else {
      notifyListeners();
    }
    unawaited(_countDocs());
    unawaited(_readCommands());
  }

  /// Reads the server's presets. Best effort: a server that will not list them leaves `/reset`
  /// alone in the menu, and a preset typed in full still runs, since the server expands it.
  Future<void> _readCommands() async {
    final server = _server;
    try {
      final presets = await _api.slashCommands();
      if (_server != server) return;
      _presets = presets;
      notifyListeners();
    } on ApiException {
      return;
    }
  }

  /// Asks each workspace how many documents it holds, all at once. Best effort: a count that
  /// cannot be read is left out. Sources reports the active workspace's own count.
  Future<void> _countDocs() async {
    Future<void> count(String slug) async {
      try {
        docCounts[slug] = (await _api.workspace(slug)).documents.length;
      } on ApiException {
        return;
      }
    }

    await Future.wait([
      for (final w in workspaces)
        if (w.slug != activeSlug && !docCounts.containsKey(w.slug))
          count(w.slug),
    ]);
    notifyListeners();
  }

  void setDocCount(String slug, int count) {
    if (docCounts[slug] == count) return;
    docCounts[slug] = count;
    notifyListeners();
  }

  /// Shows workspace [slug] on its newest chat, or a draft when it has none.
  Future<void> select(String? slug) async {
    activeSlug = slug;
    _draft.clear();
    final last = slug == null ? null : threadsOf(slug).lastOrNull;
    await open(last?.slug);
  }

  /// Shows chat [threadSlug] of the active workspace, reading its turns the first time.
  Future<void> open(String? threadSlug) async {
    activeThread = threadSlug;
    _clearLinkNotice();
    notifyListeners();
    final slug = activeSlug;
    if (slug == null || threadSlug == null || _turns.containsKey(threadSlug)) {
      return;
    }
    final server = _server;
    await _try('Could not read the chat', () async {
      final history = await _api.history(slug, threadSlug);
      if (_server != server) return;
      _turns[threadSlug] = [for (final m in history) Turn.saved(m)];
    });
  }

  /// Starts a draft, unless the chat on screen is already empty.
  void newChat() {
    if (turns.isEmpty) return;
    _draft.clear();
    activeThread = null;
    notifyListeners();
  }

  Future<void> createWorkspace(String name) {
    final server = _server;
    return _try('Could not make the workspace', () async {
      final made = await _api.createWorkspace(name.trim());
      if (_server != server) return;
      workspaces = [...workspaces, made];
      _threads[made.slug] = [];
      docCounts[made.slug] = 0;
      await select(made.slug);
    });
  }

  /// Renames workspace [slug]. When the server answers with a new slug, the workspaces are read
  /// again and the renamed one is shown.
  Future<void> renameWorkspace(String slug, String name) async {
    final clean = name.trim();
    final old = workspaces.where((w) => w.slug == slug).firstOrNull;
    if (old == null || clean.isEmpty || clean == old.name) return;
    final server = _server;
    await _try('Could not rename the workspace', () async {
      final renamed = await _api.renameWorkspace(slug, clean);
      if (_server != server) return;
      if (renamed.slug != slug) {
        final shown = activeSlug == slug;
        await load();
        if (shown) await select(renamed.slug);
        return;
      }
      workspaces = [
        for (final w in workspaces)
          w.slug == slug
              ? Workspace(
                  slug: slug,
                  name: renamed.name,
                  threads: w.threads,
                  documents: w.documents,
                  prompt: w.prompt,
                  settings: w.settings,
                )
              : w,
      ];
    });
  }

  /// Deletes workspace [slug] with its chats, unless an answer is running in it. Shows the first
  /// workspace left when it was the one on screen.
  Future<void> deleteWorkspace(String slug) async {
    if (answeringIn(slug)) return;
    final server = _server;
    await _try('Could not delete the workspace', () async {
      await _api.deleteWorkspace(slug);
      if (_server != server) return;
      for (final t in threadsOf(slug)) {
        _turns.remove(t.slug);
        _named.remove(t.slug);
      }
      _threads.remove(slug);
      docCounts.remove(slug);
      workspaces = [
        for (final w in workspaces)
          if (w.slug != slug) w,
      ];
      unawaited(_prefs.setOff(slug, const []));
      if (activeSlug == slug) await select(workspaces.firstOrNull?.slug);
    });
  }

  Future<void> rename(String threadSlug, String name) async {
    final slug = activeSlug;
    final clean = name.trim();
    if (slug == null || clean.isEmpty) return;
    final server = _server;
    await _try('Could not rename the chat', () async {
      await _api.renameThread(slug, threadSlug, clean);
      if (_server != server) return;
      _named.add(threadSlug);
      _replace(slug, Thread(slug: threadSlug, name: clean));
    });
  }

  /// Deletes chat [threadSlug], unless it is answering. Shows the chat before it, or a draft.
  Future<void> delete(String threadSlug) async {
    final slug = activeSlug;
    if (slug == null || isAnswering(threadSlug)) return;
    final server = _server;
    await _try('Could not delete the chat', () async {
      await _api.deleteThread(slug, threadSlug);
      if (_server != server) return;
      final list = _threads[slug] ?? [];
      final at = list.indexWhere((t) => t.slug == threadSlug);
      if (at >= 0) list.removeAt(at);
      _turns.remove(threadSlug);
      if (activeThread == threadSlug) {
        _draft.clear();
        await open(
          list.isEmpty ? null : list[at.clamp(0, list.length - 1)].slug,
        );
      }
    });
  }

  /// Asks [message], with [attachments], in the chat on screen, making its thread first when it
  /// is a draft. A message that [resetsChat] clears the chat instead.
  Future<void> send(
    String message, {
    List<Attachment> attachments = const [],
  }) async {
    final slug = activeSlug;
    final text = message.trim();
    if (slug == null || text.isEmpty || busy || !ready) return;
    _clearLinkNotice();
    if (resetsChat(text, _presets)) return _reset(slug);
    final user = Turn.user(
      text,
      attachments: [for (final a in attachments) a.name],
    );
    final answer = Turn.answer();
    final turns = [...this.turns, user, answer];
    final first = this.turns.every((t) => t.role != Role.user);
    final running = _running = _Running(answer, slug)..thread = activeThread;
    final server = _server;
    _setTurns(turns);
    notifyListeners();

    var threadSlug = activeThread;
    if (threadSlug == null) {
      try {
        final made = await _api.createThread(slug);
        // A new server has started afresh: the chat belongs to the old one.
        if (_server != server) return;
        threadSlug = made.slug;
        _threads[slug] = [...threadsOf(slug), made];
        _turns[made.slug] = turns;
        if (activeSlug == slug && activeThread == null) {
          _draft.clear();
          activeThread = made.slug;
        }
        running.thread = made.slug;
      } on ApiException catch (error) {
        _finish(running, error: error.message);
        return;
      }
      // Stopped while the thread was being made: the chat stays, the answer does not run.
      if (!identical(_running, running)) {
        notifyListeners();
        return;
      }
    }
    final thread = threadSlug;
    running.stream = _api
        .streamChat(slug, thread, text, attachments: attachments)
        .listen(
          (event) => switch (event) {
            TextChunk(:final text) => answer._grow(text),
            StatusChunk(:final text) => answer._setStatus(text),
            WholeAnswer(:final text) => answer._replace(text),
            ChatDone(:final citations) => answer.citations = citations,
          },
          onError: (Object error) => _finish(
            running,
            error: error is ApiException ? error.message : '$error',
          ),
          onDone: () {
            _finish(running);
            if (first && !_named.contains(thread)) {
              unawaited(_nameAfter(slug, thread, text));
            }
          },
          cancelOnError: true,
        );
  }

  /// Clears the history of the chat on screen, on the server and here. A draft has none, so it
  /// is only emptied.
  Future<void> _reset(String slug) async {
    final thread = activeThread;
    if (thread == null) {
      _draft.clear();
      notifyListeners();
      return;
    }
    final server = _server;
    await _try('Could not clear the chat', () async {
      await _api.resetChat(slug, thread);
      if (_server != server) return;
      _turns[thread] = [];
    });
  }

  /// Stops the running answer, keeping what came so far.
  void stop() {
    final running = _running;
    if (running == null) return;
    running.stream?.cancel();
    if (running.answer.text.isEmpty) running.answer.text = 'Stopped.';
    _finish(running);
  }

  /// Ends [running], with [error] when it failed, unless it was already stopped or dropped.
  void _finish(_Running running, {String? error}) {
    if (!identical(_running, running)) return;
    _running = null;
    running.answer
      ..streaming = false
      ..status = null
      ..error = error
      ..notifyListeners();
    notifyListeners();
  }

  /// Names a new chat after its first message, unless it was renamed meanwhile.
  Future<void> _nameAfter(String slug, String thread, String message) async {
    final name = defaultTitle(message);
    try {
      await _api.renameThread(slug, thread, name);
      if (!_named.contains(thread)) {
        _replace(slug, Thread(slug: thread, name: name));
      }
    } on ApiException {
      // The chat keeps its old name; nothing else depends on it.
    }
  }

  void _setTurns(List<Turn> turns) {
    if (activeThread == null) {
      _draft
        ..clear()
        ..addAll(turns);
    } else {
      _turns[activeThread!] = turns;
    }
  }

  void _replace(String slug, Thread thread) {
    _threads[slug] = [
      for (final t in threadsOf(slug)) t.slug == thread.slug ? thread : t,
    ];
    notifyListeners();
  }

  /// Shows why a link in an answer did not open, for [linkNoticeFor].
  void reportLink(String title, String text) {
    linkNotice = Notice(title, text);
    _linkTimer?.cancel();
    _linkTimer = Timer(linkNoticeFor, () {
      linkNotice = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void _clearLinkNotice() {
    _linkTimer?.cancel();
    _linkTimer = null;
    linkNotice = null;
  }

  Future<void> _try(String failTitle, Future<void> Function() op) async {
    try {
      await op();
      problem = null;
    } on ApiException catch (error) {
      problem = Notice(failTitle, error.message);
    }
    notifyListeners();
  }
}
