import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/chat.dart';
import '../../core/connection.dart';
import '../../core/ports.dart';
import '../../core/server_models.dart';
import 'answer_bytes.dart';
import 'answer_waits.dart';
import 'fleeting.dart';
import 'notice.dart';
import 'prefs_controller.dart';
import 'settings_controller.dart';
import 'turn.dart';

/// A chat [ChatController.delete] took out of the list and has not deleted on the server yet.
class _Deleted {
  const _Deleted({
    required this.server,
    required this.slug,
    required this.chat,
    required this.at,
    required this.turns,
    required this.open,
  });

  /// The server it is on, which the delete goes to even after another is in use.
  final Connection server;
  final String slug;
  final Thread chat;

  /// Where it was in its workspace's list.
  final int at;
  final List<Turn>? turns;

  /// Whether it was on screen.
  final bool open;
}

/// An answer running: the chat it belongs to, null while its draft's thread is being made, and
/// the stream it reads.
class _Running {
  _Running(this.answer, this.slug);

  final Turn answer;

  /// The workspace the answer runs in.
  final String slug;
  String? thread;
  StreamSubscription<ChatEvent>? stream;

  /// The message a chat this answer's message made is named after when the answer ends, however
  /// it ends; null for a chat that already had a name.
  String? nameAs;
}

/// The workspaces and their chats, the chat on screen, and the answers running.
///
/// One answer runs at a time in each workspace, since AnythingLLM gives an agent run no thread
/// of its own.
///
/// A chat not yet asked anything is a draft: it lives only here until its first message, which
/// makes the thread on the server. Everything it knows is about the server in [_settings]; a new
/// server starts it afresh.
class ChatController extends ChangeNotifier {
  ChatController(this._api, this._settings, this._prefs)
    : _server = _settings.connection {
    _settings.addListener(_serverChanged);
    unawaited(_prefs.useServer(_server?.baseUrl));
  }

  final AnythingLlmApi _api;
  final SettingsController _settings;
  final PrefsController _prefs;

  /// The server the fields below describe.
  Connection? _server;

  /// The server the workspaces and chats are about.
  Connection? get server => _server;

  List<Workspace> workspaces = const [];

  /// Each workspace's chats, newest last, by workspace slug.
  final Map<String, List<Thread>> _threads = {};

  /// How many documents each workspace holds, for the ones read so far.
  final Map<String, int> docCounts = {};

  String? activeSlug;

  /// The chat on screen, or null for a draft.
  String? activeThread;

  final Map<String, List<Turn>> _turns = {};
  List<Turn> _draft = [];

  /// The chats whose names the person chose, which the first message does not rename.
  final Set<String> _named = {};

  /// The last answer that ran to its end, neither stopped nor failed, or that the server saved
  /// after the connection dropped.
  Turn? get finished => _finished?.turn;

  /// The workspace and chat of [finished].
  ({String slug, String thread})? get finishedIn => switch (_finished) {
    (:final slug, :final thread, turn: _) => (slug: slug, thread: thread),
    null => null,
  };
  ({Turn turn, String slug, String thread})? _finished;

  /// The answers whose connection dropped, read for until the server saved them.
  late final waits = AnswerWaits(
    _api,
    turnsOf: (thread) => _turns[thread],
    saved: (slug, thread, saved) {
      _turns[thread] = saved;
      _markFinished(saved.last, slug, thread);
    },
    changed: notifyListeners,
  );

  /// Whether an answer is running or [Turn.waiting] anywhere, which the app keeps alive for.
  bool get working => _runs.isNotEmpty || waits.any;

  /// The workspace of an answer running or waiting, for the note that keeps the app alive.
  String? get workingIn => _runs.firstOrNull?.slug ?? waits.firstSlug;

  /// The answers running, at most one in each workspace.
  final _runs = <_Running>[];

  /// What waits for each chat's composer, by chat (null for a new one): what another app shared
  /// ([putInComposer]). The composer takes it with [takeForComposer].
  final _forComposer =
      <String?, ({String text, List<Attachment> attachments})>{};

  /// What waits for the chat on screen's composer, with its files; null once taken, or when it
  /// waits in another chat.
  ({String text, List<Attachment> attachments})? takeForComposer() =>
      _forComposer.remove(activeThread);

  /// Puts [text] and [attachments] in the composer of the chat on screen, for the person to
  /// ask about them.
  void putInComposer(String text, List<Attachment> attachments) {
    _forComposer[activeThread] = (text: text, attachments: attachments);
    notifyListeners();
  }

  /// How many messages have been sent, so the chat can bring each new one into view.
  int get sends => _sends;
  int _sends = 0;

  bool loading = false;

  /// Whether the last read of the workspaces failed: the server is out of reach or refused.
  final unreachable = ValueNotifier(false);

  /// Counts the drafts started, so a draft's first message does not take the person away from a
  /// newer draft when its thread is made.
  int _draftGo = 0;

  /// Why the last load or change failed.
  Notice? problem;

  /// Why a link in an answer did not open. It clears after [linkNoticeFor], or on the next
  /// message or chat opened.
  Notice? get linkNotice => _link.value;

  late final _link = Fleeting<Notice>(linkNoticeFor, (_) => notifyListeners());

  /// The files and images answers show, read once per server.
  late final bytes = AnswerBytes(_api, report: report);

  static const linkNoticeFor = Duration(seconds: 6);

  Workspace? get active =>
      workspaces.where((w) => w.slug == activeSlug).firstOrNull;

  List<Thread> threadsOf(String slug) => _threads[slug] ?? const [];

  Thread? get thread => activeSlug == null
      ? null
      : threadsOf(activeSlug!).where((t) => t.slug == activeThread).firstOrNull;

  String get title => thread?.name ?? newChatName;

  /// The turns of the chat on screen. A list handed out here is never changed afterwards: every
  /// change sets a new list, since the view may still be drawing from the old one.
  List<Turn> get turns =>
      activeThread == null ? _draft : (_turns[activeThread] ?? const []);

  /// Whether the chat on screen can take no message now: a chat of its workspace answers, this
  /// one or another.
  bool get busy => workspaceAnswering;

  /// Whether the chat on screen can take a message: a draft, or a chat whose history is read.
  bool get ready => activeThread == null || _turns.containsKey(activeThread);

  /// The answer running in the chat on screen, or null.
  _Running? get _here {
    final turns = this.turns;
    return _runs.where((r) => turns.contains(r.answer)).firstOrNull;
  }

  /// Whether the chat on screen is answering.
  bool get answeringHere => _here != null;

  /// The chats whose answer ended, neither failed nor stopped, while another chat was on
  /// screen, until they are opened, each to its workspace's slug. Kept for this run only.
  final _ready = <String, String>{};

  /// Whether chat [thread]'s answer is ready and not yet seen.
  bool isReady(String thread) => _ready.containsKey(thread);

  /// Whether a chat of workspace [slug] has an answer ready.
  bool readyIn(String slug) => _ready.containsValue(slug);

  bool isAnswering(String thread) => _runs.any((r) => r.thread == thread);

  /// The answer running in the chat on screen, or null. It notifies on each chunk, which this
  /// controller does not.
  Turn? get runningHere => _here?.answer;

  /// Whether [refresh] is reading the server again.
  bool get refreshing => _refreshing;
  bool _refreshing = false;

  /// Reads the workspaces and the chat on screen again, for when the connection dropped and
  /// what shows may be stale or stuck. An answer still running in this chat is let go of first,
  /// not stopped: the server may finish it, and it shows when the chat is read again. A chat
  /// deleted on the server gives way to its workspace's newest chat.
  Future<void> refresh() async {
    if (_server == null || _refreshing) return;
    _refreshing = true;
    if (_here case final running?) {
      unawaited(running.stream?.cancel());
      _finish(
        running,
        error:
            'Let go of this answer to read the chat again. The server may still finish '
            'it; refresh again later to see it.',
      );
    }
    notifyListeners();
    final slug = activeSlug;
    final thread = activeThread;
    try {
      await load();
      // Another chat is on screen now, opened by load or by the person, and read as it opened.
      if (activeSlug != slug || activeThread != thread) return;
      if (slug != null &&
          thread != null &&
          !isAnswering(thread) &&
          !threadsOf(slug).any((t) => t.slug == thread)) {
        _turns.remove(thread);
        await select(slug);
      } else {
        await open(thread, again: true);
      }
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  /// Whether a chat of workspace [slug] is answering, a draft whose chat is being made included.
  bool answeringIn(String slug) => _runs.any((r) => r.slug == slug);

  /// Whether a chat of the workspace on screen is answering, this one or another.
  bool get workspaceAnswering => activeSlug != null && answeringIn(activeSlug!);

  @override
  void dispose() {
    // The last chance to send a delete still waiting to be undone.
    unawaited(flushDelete());
    _disposed = true;
    _settings.removeListener(_serverChanged);
    for (final running in _runs) {
      running.stream?.cancel();
    }
    waits.clear();
    _link.take();
    unreachable.dispose();
    super.dispose();
  }

  void _serverChanged() {
    final now = _settings.connection;
    if (now == _server) return;
    // A delete still waiting to be undone goes to the server it was made on.
    unawaited(flushDelete());
    _server = now;
    unawaited(_prefs.useServer(_server?.baseUrl));
    for (final running in _runs) {
      running.stream?.cancel();
    }
    _runs.clear();
    waits.clear();
    _forComposer.clear();
    workspaces = const [];
    _threads.clear();
    _turns.clear();
    _ready.clear();
    _draft = [];
    bytes.clear();
    docCounts.clear();
    loading = false;
    unreachable.value = false;
    activeSlug = null;
    activeThread = null;
    problem = null;
    _link.take();
    notifyListeners();
    if (_server != null) unawaited(load());
  }

  /// Reads the workspaces and their chats, keeping the one on screen when it still exists.
  Future<void> load() async {
    if (_server == null) return;
    final server = _server;
    loading = true;
    notifyListeners();
    var failed = true;
    await _try('Could not read the workspaces', () async {
      final read = await _api.workspaces();
      if (_server != server) return;
      failed = false;
      workspaces = read;
      _threads
        ..clear()
        ..addAll({
          for (final w in workspaces) w.slug: [...w.threads],
        });
      // A chat deleted in the list but not yet on the server is still in the server's list.
      if (_deleted.value case final deleted?
          when _threads.containsKey(deleted.slug)) {
        _threads[deleted.slug] = [
          for (final t in _threads[deleted.slug]!)
            if (t.slug != deleted.chat.slug) t,
        ];
      }
    });
    if (_server != server) return;
    loading = false;
    unreachable.value = failed;
    final tapped = failed ? null : _tapped;
    if (!failed) _tapped = null;
    if (tapped case (final slug, final thread)
        when workspaces.any((w) => w.slug == slug)) {
      await select(slug, thread: thread);
    } else if (active == null) {
      final (slug, thread) = _startChat;
      await select(slug, thread: thread);
    } else {
      notifyListeners();
    }
    unawaited(_countDocs());
  }

  /// The chat a tapped notification asked for before the workspaces were read, which [load]
  /// opens in place of the last chat.
  (String, String)? _tapped;

  /// Opens chat [thread] of workspace [slug], as a tapped notification asks. Before the
  /// workspaces are read, as when the tap started the app, [load] opens it once they are.
  Future<void> openTapped(String slug, String thread) {
    if (_server == null || workspaces.isEmpty) {
      _tapped = (slug, thread);
      return Future.value();
    }
    return select(slug, thread: thread);
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
    if (last == null ||
        last.server != _server?.baseUrl ||
        !workspaces.any((w) => w.slug == last.slug)) {
      return (_firstSlug, null);
    }
    final kept = threadsOf(last.slug).any((t) => t.slug == last.thread);
    return (last.slug, kept ? last.thread : null);
  }

  /// Remembers the chat on screen as the one to open at start.
  void _rememberChat() {
    if (activeSlug case final slug?) {
      unawaited(_prefs.showChat(slug, activeThread));
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
    _freshDraft();
    await open(
      thread ?? (slug == null ? null : threadsOf(slug).lastOrNull?.slug),
    );
  }

  /// Shows chat [threadSlug] of the active workspace, reading its turns the first time, and
  /// again when its last answer is [Turn.unfinished] or the reading is asked for [again], so
  /// what the server saved since shows.
  Future<void> open(String? threadSlug, {bool again = false}) async {
    activeThread = threadSlug;
    if (threadSlug != null) _ready.remove(threadSlug);
    // What waits for the composer goes back only in its own chat.
    _forComposer.removeWhere((thread, _) => thread != threadSlug);
    _link.take();
    _rememberChat();
    notifyListeners();
    final slug = activeSlug;
    if (slug == null || threadSlug == null) return;
    // An answer waited for is checked for, which also says when it is ready.
    if (waits.has(threadSlug)) return waits.check(threadSlug);
    final known = _turns[threadSlug];
    if (known != null &&
        (isAnswering(threadSlug) ||
            (!again && known.lastOrNull?.unfinished != true))) {
      return;
    }
    final server = _server;
    await _try('Could not read the chat', () async {
      final history = await _api.history(slug, threadSlug);
      if (_server != server || isAnswering(threadSlug)) return;
      // An answer the server is still writing is saved only once it ends; until then the chat
      // keeps what it showed, and stays unfinished so it is read again. A finished chat read
      // [again] takes what the server has, though it was cleared or cut short elsewhere.
      if (known != null &&
          known.lastOrNull?.unfinished == true &&
          history.length < known.length) {
        return;
      }
      _turns[threadSlug] = [for (final m in history) Turn.saved(m)];
    });
  }

  /// Empties the draft, so a send or read meant for the one before leaves it alone.
  void _freshDraft() {
    _draft = [];
    _draftGo++;
  }

  /// Starts a draft, unless the chat on screen is already empty: a draft, or a chat read with no
  /// turns. A chat whose turns are still being read is not empty.
  void newChat() {
    final thread = activeThread;
    if (thread == null ? _draft.isEmpty : _turns[thread]?.isEmpty == true) {
      return;
    }
    _freshDraft();
    activeThread = null;
    _rememberChat();
    notifyListeners();
  }

  /// Makes workspace [name] with [prompt] as its instructions and opens it. An empty prompt is
  /// none, so the server's default applies.
  Future<void> createWorkspace(String name, {String prompt = ''}) {
    final server = _server;
    return _try('Could not make the workspace', () async {
      final made = await _api.createWorkspace(
        name.trim(),
        prompt: prompt.trim().isEmpty ? null : prompt,
      );
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

  /// How long a deleted chat can be put back before it is deleted on the server.
  static const undoFor = Duration(seconds: 6);

  /// The chat deleted from the list but not yet on the server, while it can be put back.
  late final _deleted = Fleeting<_Deleted>(undoFor, (d) => unawaited(_send(d)));

  /// Whether [dispose] ran, after which a delete that comes back changes nothing.
  bool _disposed = false;

  /// The name of the chat that [undoDelete] would put back, or null.
  String? get deletedChat => _deleted.value?.chat.name;

  /// Takes chat [threadSlug] of the workspace on screen out of the list at once, and deletes it
  /// on the server [undoFor] later, unless [undoDelete] puts it back first. Another delete, or
  /// [flushDelete], sends the one waiting at once. The chat on screen gives way to a new chat,
  /// a draft in the same workspace.
  Future<void> delete(String threadSlug) async {
    final slug = activeSlug;
    final server = _server;
    if (slug == null || server == null || isAnswering(threadSlug)) return;
    unawaited(flushDelete());
    final was = threadsOf(slug);
    final at = was.indexWhere((t) => t.slug == threadSlug);
    if (at < 0) return;
    final open = activeThread == threadSlug;
    _deleted.show(
      _Deleted(
        server: server,
        slug: slug,
        chat: was[at],
        at: at,
        turns: _turns[threadSlug],
        open: open,
      ),
    );
    final list = [...was]..removeAt(at);
    _threads[slug] = list;
    _turns.remove(threadSlug);
    if (open) {
      _freshDraft();
      await this.open(null);
    } else {
      notifyListeners();
    }
  }

  /// Puts the chat [delete] took out back where it was, and on screen if it was.
  Future<void> undoDelete() async {
    final deleted = _deleted.take();
    if (deleted == null) return;
    _restore(deleted);
    if (deleted.open && activeSlug == deleted.slug) {
      await open(deleted.chat.slug);
    } else {
      notifyListeners();
    }
  }

  /// Deletes on the server, now, the chat [delete] took out, on the server it was on. A delete
  /// the server refuses puts the chat back.
  Future<void> flushDelete() => _send(_deleted.take());

  /// Deletes [deleted] on its server, putting it back when the server refuses.
  Future<void> _send(_Deleted? deleted) async {
    if (deleted == null) return;
    notifyListeners();
    final thread = deleted.chat.slug;
    try {
      await _api.deleteThread(deleted.slug, thread, on: deleted.server);
      if (!_disposed && _server == deleted.server) {
        unawaited(_prefs.forgetChat(deleted.slug, thread));
      }
    } on ApiException catch (error) {
      if (_disposed || !_restore(deleted)) return;
      problem = Notice('Could not delete the chat', error.message);
      notifyListeners();
    }
  }

  /// Puts [deleted] back in its list, and says whether it was its server's to put back.
  bool _restore(_Deleted deleted) {
    if (_server != deleted.server) return false;
    final list = [...threadsOf(deleted.slug)];
    if (list.any((t) => t.slug == deleted.chat.slug)) return true;
    list.insert(deleted.at.clamp(0, list.length), deleted.chat);
    _threads[deleted.slug] = list;
    if (deleted.turns case final turns?) _turns[deleted.chat.slug] = turns;
    return true;
  }

  /// Asks [message], with [attachments], in the chat on screen, making its thread first when it
  /// is a draft. True when the message was taken.
  Future<bool> send(
    String message, {
    List<Attachment> attachments = const [],
  }) async {
    final slug = activeSlug;
    final text = message.trim();
    if (slug == null || text.isEmpty || busy || !ready) return false;
    _link.take();
    final user = Turn.user(
      text,
      attachments: [
        for (final a in attachments)
          a.isImage ? SentFile.picture(a.name, a.bytes) : SentFile(a.name),
      ],
    );
    final answer = Turn.answer();
    final turns = [...this.turns, user, answer];
    final running = _Running(answer, slug)..thread = activeThread;
    _runs.add(running);
    final server = _server;
    final draftGo = _draftGo;
    _setTurns(turns);
    _sends++;
    notifyListeners();

    var threadSlug = activeThread;
    if (threadSlug == null) {
      try {
        final made = await _api.createThread(slug);
        // A new server has started afresh: the chat belongs to the old one.
        if (_server != server) return true;
        threadSlug = made.slug;
        _threads[slug] = [...threadsOf(slug), made];
        _turns[made.slug] = turns;
        if (activeSlug == slug && activeThread == null && _draftGo == draftGo) {
          _draft = [];
          activeThread = made.slug;
          _rememberChat();
          notifyListeners();
        }
        running
          ..thread = made.slug
          ..nameAs = text;
      } on ApiException catch (error) {
        _finish(running, error: error.message);
        return true;
      }
      // Stopped while the thread was being made: the chat stays, the answer does not run.
      if (!_runs.contains(running)) {
        notifyListeners();
        return true;
      }
    }
    final thread = threadSlug;
    _follow(
      running,
      _api.streamChat(slug, thread, text, attachments: attachments),
    );
    return true;
  }

  /// Reads [events] into the answer [running] is, until it ends or fails.
  void _follow(_Running running, Stream<ChatEvent> events) {
    running.stream = events.listen(
      running.answer.take,
      onError: (Object error) {
        if (error is CutOff) return _wait(running);
        _finish(
          running,
          error: error is ApiException ? error.message : '$error',
        );
      },
      onDone: () => _finish(running),
      cancelOnError: true,
    );
  }

  /// Whether [retry] can ask the last question again: nothing runs, the chat is not being read
  /// again by [refresh], which would take the turns it replaces, the chat's last turn is an
  /// answer, and its question went without files, whose bytes are not kept.
  bool get canRetry {
    final turns = this.turns;
    return !busy &&
        !_refreshing &&
        ready &&
        turns.length >= 2 &&
        turns.last.role == Role.assistant &&
        !turns.last.waiting &&
        turns[turns.length - 2].role == Role.user &&
        turns[turns.length - 2].attachments.isEmpty;
  }

  /// Asks the chat's last question again, in place of its answer here. The server keeps the old
  /// exchange too, which shows again when the chat is next read.
  Future<void> retry() async {
    if (!canRetry) return;
    final turns = this.turns;
    final question = turns[turns.length - 2];
    _setTurns(turns.sublist(0, turns.length - 2));
    await send(question.text);
  }

  /// Ends [running], whose connection dropped, without failing it: AnythingLLM may still finish
  /// the answer, so the chat's history is read until it holds it.
  void _wait(_Running running) {
    final thread = running.thread;
    if (thread == null) {
      return _finish(running, error: 'The connection dropped.');
    }
    // Waiting before the run ends, so [working] holds throughout.
    waits.start(running.answer, running.slug, thread);
    _finish(running);
  }

  /// Reads each chat whose answer is [Turn.waiting] now, as when the app comes back to the
  /// front or Check now is tapped.
  Future<void> checkWaiting() => waits.checkAll();

  /// Stops the answer running in the chat on screen, keeping what came so far. Letting go of the
  /// response is what stops it on the server.
  void stop() {
    final running = _here;
    if (running == null) return;
    running.stream?.cancel();
    running.answer.stopped = true;
    if (running.answer.text.isEmpty) running.answer.text = 'Stopped.';
    _finish(running);
  }

  /// Records [turn] as the last answer that ran to its end, and marks its chat ready unless it
  /// is the one on screen.
  void _markFinished(Turn turn, String slug, String thread) {
    _finished = (turn: turn, slug: slug, thread: thread);
    if (thread != activeThread || slug != activeSlug) _ready[thread] = slug;
  }

  /// Ends [running], with [error] when it failed, unless it was already stopped or dropped.
  void _finish(_Running running, {String? error}) {
    if (!_runs.remove(running)) return;
    if ((running.thread, running.nameAs) case (final thread?, final message?)
        when !_named.contains(thread)) {
      unawaited(_nameAfter(running.slug, thread, message));
    }
    if ((error, running.thread) case (null, final thread?)
        when !running.answer.unfinished) {
      _markFinished(running.answer, running.slug, thread);
    }
    // An answer in a chat, however it ended, is a use of it, for Recent.
    if (running.thread case final thread?) {
      unawaited(_prefs.useChat(running.slug, thread));
    }
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
    final server = _server;
    try {
      await _api.renameThread(slug, thread, name);
      if (_server == server && !_named.contains(thread)) {
        _replace(slug, Thread(slug: thread, name: name));
      }
    } on ApiException {
      // The chat keeps its old name; nothing else depends on it.
    }
  }

  void _setTurns(List<Turn> turns) {
    if (activeThread == null) {
      _draft = turns;
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

  /// Shows [text] as [problem], titled [title].
  void report(String title, String text) {
    problem = Notice(title, text);
    notifyListeners();
  }

  /// Shows why a link in an answer did not open, for [linkNoticeFor].
  void reportLink(String title, String text) {
    _link.show(Notice(title, text));
    notifyListeners();
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
