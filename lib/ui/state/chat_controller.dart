import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/chat.dart';
import '../../core/commands.dart';
import '../../core/connection.dart';
import '../../core/outputs.dart';
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
      files = message.files,
      metrics = message.metrics,
      chatId = message.chatId,
      feedback = message.feedback,
      streaming = false;

  final Role role;
  String text;

  /// The names of the files sent with a question.
  List<String> attachments = const [];
  List<Citation> citations = const [];

  /// What an agent made with the answer.
  List<GeneratedFile> files = const [];

  /// How the answer ran, when the server measured it.
  AnswerMetrics? metrics;

  /// The server's id for the exchange, once it has said; a question and its answer share it.
  int? chatId;

  /// Whether the answer was marked good or bad, or null when neither.
  bool? feedback;
  bool streaming;

  /// Why the answer failed, or null.
  String? error;

  /// Whether the person stopped the answer.
  bool stopped = false;

  /// Whether the server may finish this answer after the app let go of it: it failed or was
  /// stopped.
  bool get unfinished => role == Role.assistant && (error != null || stopped);

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

  void _mark(bool? good) {
    feedback = good;
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
    : _server = _settings.connection?.withPassword(null),
      _password = _settings.connection?.password {
    _settings.addListener(_serverChanged);
  }

  final AnythingLlmApi _api;
  final SettingsController _settings;
  final PrefsController _prefs;

  /// The server the fields below describe: its address and key, without the password, so
  /// saving or forgetting one does not start afresh.
  Connection? _server;

  /// The server the workspaces and chats are about, without its optional web UI password.
  Connection? get server => _server;

  /// The server's saved password, which signs in to the web UI's own routes.
  String? _password;

  /// Whether a password for the server is saved, so Retry and Edit replace the old exchange on
  /// the server and an answer can be marked good or bad.
  bool get signedIn => _password != null;

  /// The question being edited: sending replaces it and everything after it. Only while
  /// [signedIn].
  Turn? editing;

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

  /// Why the server's presets are missing from [commands], or null when they were read.
  String? commandsNote;

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

  /// The bytes of each file an agent made, by storage name, read once per server.
  final Map<String, Future<List<int>?>> _madeFiles = {};

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

  /// Whether the chat on screen is being cleared on the server.
  bool get clearing => _clearing;
  bool _clearing = false;

  /// Whether an answer runs, a chat is being cleared or exchanges are being dropped, so no
  /// message can be sent.
  bool get busy => _running != null || _clearing || _dropping;
  bool _dropping = false;

  /// Whether the chat on screen can take a message: a draft, or a chat whose history is read.
  bool get ready => activeThread == null || _turns.containsKey(activeThread);

  /// Whether the chat on screen is the one answering.
  bool get answeringHere =>
      _running != null && turns.contains(_running!.answer);

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
    final now = _settings.connection;
    if (now?.withPassword(null) == _server) {
      if (now?.password == _password) return;
      _password = now?.password;
      if (!signedIn) editing = null;
      notifyListeners();
      if (_server != null) unawaited(_readCommands());
      return;
    }
    _server = now?.withPassword(null);
    _password = now?.password;
    editing = null;
    _running?.stream?.cancel();
    _running = null;
    workspaces = const [];
    _threads.clear();
    _turns.clear();
    _draft.clear();
    _madeFiles.clear();
    docCounts.clear();
    loading = false;
    _clearing = false;
    _presets = const [];
    commandsNote = null;
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
    final server = _server;
    loading = true;
    notifyListeners();
    await _try('Could not read the workspaces', () async {
      final read = await _api.workspaces();
      if (_server != server) return;
      workspaces = read;
      _threads
        ..clear()
        ..addAll({
          for (final w in workspaces) w.slug: [...w.threads],
        });
    });
    if (_server != server) return;
    loading = false;
    if (active == null) {
      final (slug, thread) = _startChat;
      await select(slug, thread: thread);
    } else {
      notifyListeners();
    }
    unawaited(_countDocs());
    unawaited(_readCommands());
  }

  /// Reads the server's presets. Best effort: a server that will not list them leaves `/reset`
  /// alone in the menu with [commandsNote] saying why, and a preset typed in full still runs,
  /// since the server expands it. The list needs the web UI's session, which a server with a
  /// password refuses.
  Future<void> _readCommands() async {
    final server = _server;
    try {
      final presets = await _api.slashCommands();
      if (_server != server) return;
      _presets = presets;
      commandsNote = null;
    } on ApiException catch (error) {
      if (_server != server) return;
      commandsNote = whyNoPresets(error, signedIn: signedIn);
    }
    notifyListeners();
  }

  /// Asks each workspace how many documents it holds, all at once. Best effort: a count that
  /// cannot be read is left out. Sources reports the active workspace's own count.
  Future<void> _countDocs() async {
    final server = _server;
    Future<void> count(String slug) async {
      try {
        final workspace = await _api.workspace(slug);
        if (_server != server) return;
        docCounts[slug] = workspace.documents.length;
      } on ApiException {
        return;
      }
    }

    await Future.wait([
      for (final w in workspaces)
        if (w.slug != activeSlug && !docCounts.containsKey(w.slug))
          count(w.slug),
    ]);
    if (_server != server) return;
    notifyListeners();
  }

  /// The first workspace in the order the person arranged, or null when there is none.
  String? get _firstSlug =>
      _prefs.prefs.inOrder(workspaces, (w) => w.slug).firstOrNull?.slug;

  /// The workspace and chat to open first: the last on screen while the workspace exists, on
  /// its newest chat when that chat is gone; otherwise [_firstSlug] on its newest chat.
  (String?, String?) get _startChat {
    final last = _prefs.prefs.lastChat;
    if (last == null || !workspaces.any((w) => w.slug == last.slug)) {
      return (_firstSlug, null);
    }
    final kept = threadsOf(last.slug).any((t) => t.slug == last.thread);
    return (last.slug, kept ? last.thread : null);
  }

  /// Remembers the chat on screen as the one to open at start.
  void _rememberChat() {
    if (activeSlug case final slug?) {
      unawaited(_prefs.setLastChat(slug, activeThread));
    }
  }

  void setDocCount(String slug, int count) {
    if (docCounts[slug] == count) return;
    docCounts[slug] = count;
    notifyListeners();
  }

  /// Shows workspace [slug] on chat [thread], or on its newest chat, or a draft when it has
  /// none.
  Future<void> select(String? slug, {String? thread}) async {
    activeSlug = slug;
    editing = null;
    _draft.clear();
    await open(
      thread ?? (slug == null ? null : threadsOf(slug).lastOrNull?.slug),
    );
  }

  /// Shows chat [threadSlug] of the active workspace, reading its turns the first time, and
  /// again when its last answer is [Turn.unfinished], so what the server saved since shows.
  Future<void> open(String? threadSlug) async {
    activeThread = threadSlug;
    editing = null;
    _clearLinkNotice();
    _rememberChat();
    notifyListeners();
    final slug = activeSlug;
    if (slug == null || threadSlug == null) return;
    final known = _turns[threadSlug];
    if (known != null &&
        (known.lastOrNull?.unfinished != true || isAnswering(threadSlug))) {
      return;
    }
    final server = _server;
    await _try('Could not read the chat', () async {
      final history = await _api.history(slug, threadSlug);
      if (_server != server || isAnswering(threadSlug)) return;
      _turns[threadSlug] = [for (final m in history) Turn.saved(m)];
    });
  }

  /// Starts a draft, unless the chat on screen is already empty.
  void newChat() {
    if (turns.isEmpty) return;
    _draft.clear();
    activeThread = null;
    _rememberChat();
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
    Workspace? renamed;
    await _try('Could not rename the workspace', () async {
      renamed = await _api.renameWorkspace(slug, clean);
      if (_server != server || renamed!.slug != slug) return;
      workspaces = [
        for (final w in workspaces)
          w.slug == slug ? w.withName(renamed!.name) : w,
      ];
    });
    // Read again outside the rename's own notice, so a failed read stays shown.
    if (renamed case final made? when _server == server && made.slug != slug) {
      final shown = activeSlug == slug;
      unawaited(_prefs.renameWorkspace(slug, made.slug));
      await load();
      if (shown) await select(made.slug);
    }
  }

  /// Deletes workspace [slug] with its chats, unless an answer is running in it. Shows the first
  /// workspace left, in the person's order, when it was the one on screen.
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
      unawaited(_prefs.forgetWorkspace(slug));
      if (activeSlug == slug) await select(_firstSlug);
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
    if (editing case final edited?) {
      editing = null;
      final at = this.turns.indexOf(edited);
      if (at >= 0) {
        if (!await _dropFrom(edited.chatId)) return;
        _setTurns(this.turns.sublist(0, at));
      }
    }
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
          _rememberChat();
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
            ChatDone(
              :final citations,
              :final files,
              :final metrics,
              :final chatId,
            ) =>
              answer
                ..citations = citations
                ..files = files
                ..metrics = metrics
                ..chatId = user.chatId = chatId,
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

  /// Whether [retry] can ask the last question again: nothing runs, the chat's last turn is an
  /// answer, and its question went without files, whose bytes are not kept.
  bool get canRetry {
    final turns = this.turns;
    return !busy &&
        ready &&
        turns.length >= 2 &&
        turns.last.role == Role.assistant &&
        turns[turns.length - 2].role == Role.user &&
        turns[turns.length - 2].attachments.isEmpty;
  }

  /// Asks the chat's last question again, in place of its answer. While [signedIn] the old
  /// exchange is deleted on the server first; otherwise the server keeps it too, and it shows
  /// again when the chat is next read.
  Future<void> retry() async {
    if (!canRetry) return;
    final turns = this.turns;
    final question = turns[turns.length - 2];
    if (!await _dropFrom(question.chatId ?? turns.last.chatId)) return;
    if (!identical(this.turns, turns)) return;
    _setTurns(turns.sublist(0, turns.length - 2));
    await send(question.text);
  }

  /// Starts editing [question]: sending then replaces it and everything after it on the server.
  /// Does nothing unless [signedIn] and the server has said the question's id; the composer
  /// takes its text either way.
  void edit(Turn question) {
    if (!signedIn || question.chatId == null || !turns.contains(question)) {
      return;
    }
    editing = question;
    notifyListeners();
  }

  void cancelEdit() {
    if (editing == null) return;
    editing = null;
    notifyListeners();
  }

  /// Marks [answer] good or bad on the server, or neither when it is marked so already. Shows at
  /// once, and goes back with a [problem] when the server refuses.
  Future<void> mark(Turn answer, bool good) async {
    final slug = activeSlug;
    final id = answer.chatId;
    if (!signedIn || slug == null || id == null) return;
    final was = answer.feedback;
    final now = was == good ? null : good;
    answer._mark(now);
    final server = _server;
    try {
      await _api.setFeedback(slug, id, now);
    } on ApiException catch (error) {
      if (_server != server) return;
      if (answer.feedback == now) answer._mark(was);
      problem = Notice('Could not mark the answer', error.message);
      notifyListeners();
    }
  }

  /// Deletes the chat on screen's exchanges from [chatId] on, while [signedIn] and the id is
  /// known. True when the question may then be asked: they were deleted, or there was nothing to
  /// delete with. A failure shows as [problem].
  Future<bool> _dropFrom(int? chatId) async {
    final slug = activeSlug;
    final thread = activeThread;
    if (!signedIn || chatId == null || slug == null || thread == null) {
      return true;
    }
    final server = _server;
    _dropping = true;
    notifyListeners();
    try {
      await _api.dropFrom(slug, thread, chatId);
      return _server == server && activeSlug == slug && activeThread == thread;
    } on ApiException catch (error) {
      if (_server == server) {
        problem = Notice('Could not replace the old exchange', error.message);
      }
      return false;
    } finally {
      _dropping = false;
      notifyListeners();
    }
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
    _clearing = true;
    notifyListeners();
    try {
      await _try('Could not clear the chat', () async {
        await _api.resetChat(slug, thread);
        if (_server != server) return;
        _turns[thread] = [];
      });
    } finally {
      // A new server has started afresh, clearing included.
      if (_server == server) {
        _clearing = false;
        notifyListeners();
      }
    }
  }

  /// Stops the running answer, on the server too, keeping what came so far.
  void stop() {
    final running = _running;
    if (running == null) return;
    if (running.thread case final thread? when running.stream != null) {
      unawaited(_stopOnServer(running.slug, thread));
    }
    running.stream?.cancel();
    running.answer.stopped = true;
    if (running.answer.text.isEmpty) running.answer.text = 'Stopped.';
    _finish(running);
  }

  /// Stops the chat's answer on the server, and says so when that fails: the answer then goes
  /// on there and is saved to the chat.
  Future<void> _stopOnServer(String slug, String thread) async {
    final server = _server;
    try {
      await _api.stopChat(slug, thread);
    } on ApiException catch (error) {
      if (_server != server) return;
      problem = Notice(
        'Could not stop the answer on the server',
        error.message,
      );
      notifyListeners();
    }
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

  /// The bytes of [file], which an agent made with an answer, read once; null when they could
  /// not be read, and why shows as [problem]. A failed read is tried again next time.
  Future<List<int>?> fileBytes(GeneratedFile file) =>
      _madeFiles[file.storageName] ??= _readFile(file);

  Future<List<int>?> _readFile(GeneratedFile file) async {
    final server = _server;
    try {
      return await _api.generatedFile(file.storageName);
    } on ApiException catch (error) {
      _madeFiles.remove(file.storageName);
      if (_server == server) {
        report('Could not get ${file.name}', error.message);
      }
      return null;
    }
  }

  /// Shows [text] as [problem], titled [title].
  void report(String title, String text) {
    problem = Notice(title, text);
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

  /// Runs [op], showing its failure as a [Notice] titled [failTitle]. A new server meanwhile has
  /// started afresh, so neither its success nor its failure is shown.
  Future<void> _try(String failTitle, Future<void> Function() op) async {
    final server = _server;
    try {
      await op();
      if (_server != server) return;
      problem = null;
    } on ApiException catch (error) {
      if (_server != server) return;
      problem = Notice(failTitle, error.message);
    }
    notifyListeners();
  }
}
