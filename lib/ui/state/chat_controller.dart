import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/browser.dart';
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

  /// The files sent with a question.
  List<SentFile> attachments = const [];
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

  /// Whether the answer [error] names is still being written by the relay the app lost touch
  /// with, so it will be in the chat when it is done.
  bool stillRunning = false;

  /// Whether the answer was found already running on the relay when the chat was opened, so it
  /// was written while the app was closed or out of touch.
  bool rejoined = false;

  /// Whether the person stopped the answer.
  bool stopped = false;

  /// Whether the server may finish this answer after the app let go of it: it failed or was
  /// stopped.
  bool get unfinished => role == Role.assistant && (error != null || stopped);

  /// What an agent is doing while the answer runs, such as a tool it runs, or null.
  String? status;

  /// The everythingllm browser's steps in this answer, in order, as the stream told them. A
  /// saved answer has none: its history keeps no status lines.
  List<String> browserSteps = const [];

  /// Whether the latest [status] is one of [browserSteps].
  bool get browsing => streaming && _browserStatus;
  bool _browserStatus = false;

  /// Notifies when [status] changes, which the text does far more often; a view of the
  /// browser listens here rather than to every chunk.
  Listenable get statusChanges => _statusChanges;
  final _statusChanges = ChangeNotifier();

  /// The browser cards in [text] on the [server] given, read again only when either changes.
  List<BrowserCard> _cardsOf(Uri? server) {
    if (_cards case (final read, final on, final cards)
        when identical(read, text) && on == server) {
      return cards;
    }
    final cards = browserCards(text, server: server);
    _cards = (text, server, cards);
    return cards;
  }

  (String, Uri?, List<BrowserCard>)? _cards;

  void _grow(String more) {
    text += more;
    notifyListeners();
  }

  /// Whether the status line that comes next is a browser skill's own words for the step its
  /// call began: everythingllm's skills say it right after AnythingLLM reports the call.
  bool _ownWords = false;

  void _setStatus(String line, {String? tool}) {
    status = line;
    if (tool != null) {
      _browserStatus = _ownWords = isBrowserTool(tool);
      if (_browserStatus) browserSteps = [...browserSteps, line];
    } else if (_ownWords) {
      // The skill's words name the element, so they take the place of the call's.
      _ownWords = false;
      browserSteps = [...browserSteps.take(browserSteps.length - 1), line];
    } else {
      _browserStatus = false;
    }
    notifyListeners();
    _statusChanges.notifyListeners();
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
/// One answer runs at a time in each workspace, since agent runs in one workspace share its
/// browser on the server, and at most [maxRuns] in all, when that is set.
///
/// A chat not yet asked anything is a draft: it lives only here until its first message, which
/// makes the thread on the server. Everything it knows is about the server in [_settings]; a new
/// server starts it afresh.
class ChatController extends ChangeNotifier {
  ChatController(this._api, this._settings, this._prefs, {this.maxRuns})
    : _server = _settings.connection?.withPassword(null),
      _password = _settings.connection?.password,
      _auth = _settings.auth {
    _settings.addListener(_serverChanged);
    unawaited(_prefs.useServer(_server?.baseUrl));
  }

  final AnythingLlmApi _api;
  final SettingsController _settings;
  final PrefsController _prefs;

  /// How many answers may run at once across workspaces, or null for no limit. In a browser
  /// each holds a connection open, and the browser opens only a few to one server.
  final int? maxRuns;

  /// The server the fields below describe: its address and key, without the password, so
  /// saving or forgetting one does not start afresh.
  Connection? _server;

  /// The server the workspaces and chats are about, without its optional web UI password.
  Connection? get server => _server;

  /// The server's saved password, which signs in to the web UI's own routes.
  String? _password;

  /// How the server said it signs in, or null before it has said.
  ServerAuth? _auth;

  /// Whether the web UI's own routes open: a password for the server is saved, or the server has
  /// none. Retry and Edit then replace the old exchange on the server, and an answer can be
  /// marked good or bad.
  bool get signedIn => _password != null || _auth == ServerAuth.none;

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
  List<Turn> _draft = [];

  /// The chats whose names the person chose, which the first message does not rename.
  final Set<String> _named = {};

  /// The server's slash-command presets, or none when they cannot be read.
  List<SlashCommand> _presets = const [];

  /// Why the server's presets are missing from [commands], or null when they were read.
  String? commandsNote;

  /// The commands a message can start with: `/reset`, then the server's presets.
  List<SlashCommand> get commands => withBuiltIns(_presets);

  /// The last answer that ran to its end, neither stopped nor failed.
  Turn? get finished => _finished;
  Turn? _finished;

  /// The answers running, at most one in each workspace but for one found running on the relay.
  final _runs = <_Running>[];

  /// The chats whose last message the relay refused because they were already answering, maybe
  /// on another device, while that answer may still run.
  final _refusedIn = <String>{};

  /// The messages the relay refused, by chat, which the composer takes back with [takeRefused].
  final _refused = <String, ({String text, List<Attachment> attachments})>{};

  /// Whether the chat on screen refused the last message because it was already answering,
  /// maybe on another device: its answer is followed here, and the message waits in the
  /// composer to be sent when it ends.
  bool get alreadyAnswering => _refusedIn.contains(activeThread);

  /// The message the relay refused in the chat on screen, with its files, for the composer to
  /// put back; null once taken, or when it was refused in another chat.
  ({String text, List<Attachment> attachments})? takeRefused() =>
      _refused.remove(activeThread);

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
  Notice? linkNotice;

  Timer? _linkTimer;

  /// The bytes of each file an agent made, by storage name, read once per server.
  final Map<String, Future<List<int>?>> _madeFiles = {};

  /// The last frame of each image in an answer, by address, and whether that read gave one
  /// frame and ended, so the image will not change.
  final Map<Uri, ({Uint8List frame, bool whole})> _images = {};

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

  /// Whether the chat on screen is being cleared on the server.
  bool get clearing => _clearingIn.contains(activeThread);

  /// The chats being cleared on the server.
  final _clearingIn = <String>{};

  /// The chats whose exchanges are being deleted on the server, for Retry or an edit.
  final _droppingIn = <String>{};

  /// Whether the chat on screen can take no message now: a chat of its workspace answers, this
  /// one or another, [atLimit] holds, or this chat is being cleared or its exchanges dropped.
  bool get busy => _changing(activeThread) || workspaceAnswering || atLimit;

  /// Whether chat [thread] is being cleared or its exchanges dropped on the server.
  bool _changing(String? thread) =>
      _clearingIn.contains(thread) || _droppingIn.contains(thread);

  /// Whether [maxRuns] answers are running, so no other can start.
  bool get atLimit => maxRuns != null && _runs.length >= maxRuns!;

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

  /// The browser's cards in the chat on screen's finished answers, newest first. A running
  /// answer's cards count once it ends, so the text streaming in is never parsed for one.
  Iterable<BrowserCard> get _cardsHere sync* {
    final server = _server?.uri;
    for (final turn in turns.reversed) {
      if (turn.role != Role.assistant || turn.streaming) continue;
      yield* turn._cardsOf(server).reversed;
    }
  }

  /// The newest tab's card in the chat on screen, or null.
  BrowserCard? get browserCard => _cardsHere.where((c) => !c.login).firstOrNull;

  /// The newest login request's card in the chat on screen, when no tab's card came after it.
  BrowserCard? get loginCard =>
      _cardsHere.takeWhile((c) => c.login).firstOrNull;

  /// The browser cards in [turn]'s text, on this server, read once per text.
  List<BrowserCard> cardsOf(Turn turn) => turn._cardsOf(_server?.uri);

  /// Whether the chat on screen has used the everythingllm browser, as far as it can tell: an
  /// answer has a card of it, or took browser steps while this app followed it.
  bool get usedBrowser =>
      _cardsHere.isNotEmpty ||
      turns.any((turn) => turn.browserSteps.isNotEmpty);

  /// Whether [refresh] is reading the server again.
  bool get refreshing => _refreshing;
  bool _refreshing = false;

  /// Reads the workspaces and the chat on screen again, for when the connection dropped and
  /// what shows may be stale or stuck. An answer still running in this chat is let go of first,
  /// not stopped: the server may finish it, and it shows when the chat is read again. A chat
  /// deleted on the server gives way to its workspace's newest chat. Does nothing while the
  /// chat is being cleared or its exchanges dropped, which the reading would race.
  Future<void> refresh() async {
    if (_server == null || _refreshing || _changing(activeThread)) return;
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
    _linkTimer?.cancel();
    unreachable.dispose();
    super.dispose();
  }

  void _serverChanged() {
    final now = _settings.connection;
    if (now?.withPassword(null) == _server) {
      if (now?.password == _password && _settings.auth == _auth) return;
      final newPassword = now?.password != _password;
      _password = now?.password;
      _auth = _settings.auth;
      if (!signedIn) editing = null;
      notifyListeners();
      if (newPassword && _server != null) unawaited(_readCommands());
      return;
    }
    // A delete still waiting to be undone goes to the server it was made on.
    unawaited(flushDelete());
    _server = now?.withPassword(null);
    _password = now?.password;
    _auth = _settings.auth;
    unawaited(_prefs.useServer(_server?.baseUrl));
    editing = null;
    for (final running in _runs) {
      running.stream?.cancel();
    }
    _runs.clear();
    _refusedIn.clear();
    _refused.clear();
    workspaces = const [];
    _threads.clear();
    _turns.clear();
    _ready.clear();
    _runsRead = false;
    _onScreen = null;
    _draft = [];
    _madeFiles.clear();
    _images.clear();
    docCounts.clear();
    loading = false;
    unreachable.value = false;
    _clearingIn.clear();
    _droppingIn.clear();
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
      if (_deleted case final deleted?
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
    if (active == null) {
      final (slug, thread) = _startChat;
      await select(slug, thread: thread);
    } else {
      notifyListeners();
    }
    unawaited(_countDocs());
    unawaited(_readCommands());
    // Once a server here; the app showing again asks again.
    if (!_runsRead) {
      _runsRead = true;
      unawaited(readFinishedRuns());
    }
  }

  /// Whether this server's finished runs were read at its first load.
  bool _runsRead = false;

  /// Reads the server's presets. Best effort: a server that will not list them leaves `/reset`
  /// alone in the menu with [commandsNote] saying why, and a preset typed in full still runs,
  /// since the server expands it. The list needs the web UI's session, which a server with a
  /// password refuses.
  Future<void> _readCommands() async {
    final server = _server;
    final read = ++_commandReads;
    try {
      final presets = await _api.slashCommands();
      if (_server != server || read != _commandReads) return;
      _presets = presets;
      commandsNote = null;
    } on ApiException catch (error) {
      if (_server != server || read != _commandReads) return;
      commandsNote = whyNoPresets(error, signedIn: signedIn);
    }
    notifyListeners();
  }

  /// Counts the reads of the presets, so only the latest one's answer is kept.
  var _commandReads = 0;

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
    final shown = switch ((activeSlug, activeThread)) {
      (final slug?, final thread?) => (slug: slug, thread: thread),
      _ => null,
    };
    // The chat that leaves the screen was seen until now, and so was the one that comes.
    final left = _onScreen;
    _onScreen = shown;
    if (activeSlug case final slug?) {
      unawaited(
        _prefs.showChat(
          slug,
          activeThread,
          seen: [if (left != null && left != shown) left, ?shown],
          at: DateTime.now().toUtc(),
        ),
      );
    }
  }

  /// The chat on screen as [_rememberChat] last noted it.
  ({String slug, String thread})? _onScreen;

  /// Notes that the chat on screen was seen until now, as when the app hides.
  void noteSeen() {
    if (_onScreen case final shown?) {
      unawaited(
        _prefs.setSeen(shown.slug, shown.thread, DateTime.now().toUtc()),
      );
    }
  }

  /// Reads the answers the relay holds, and marks ready each chat whose answer it finished,
  /// neither failed nor stopped, after the chat was last on screen on this device, as when the
  /// app had let go of it or was closed. A chat never seen here, and the chat on screen, get
  /// none.
  Future<void> readFinishedRuns() async {
    final server = _server;
    if (server == null) return;
    final List<RelayRun> runs;
    try {
      runs = await _api.relayRuns();
    } on ApiException {
      // A server with no relay, or one that cannot be asked, has none to mark.
      return;
    }
    if (_server != server) return;
    final threads = {
      for (final MapEntry(:key, :value) in _threads.entries)
        for (final t in value) (key, t.slug),
    };
    var marked = false;
    for (final run in runs) {
      final finished = run.finished;
      if (!run.done || finished == null) continue;
      if (run.thread == activeThread || _ready.containsKey(run.thread)) {
        continue;
      }
      if (!threads.contains((run.workspace, run.thread))) continue;
      final seen = _prefs.seenAt(run.workspace, run.thread);
      if (seen == null || !finished.isAfter(seen)) continue;
      _ready[run.thread] = run.workspace;
      marked = true;
    }
    if (marked) notifyListeners();
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
    _draft = [];
    _draftGo++;
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
    // A refused message goes back to the composer only in its own chat.
    _refused.removeWhere((thread, _) => thread != threadSlug);
    editing = null;
    _clearLinkNotice();
    _rememberChat();
    notifyListeners();
    final slug = activeSlug;
    if (slug == null || threadSlug == null) return;
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
    // Not waited for: a chat is open once its turns are read, and the lookup may take a while.
    if (_server == server && activeThread == threadSlug) {
      unawaited(_rejoin(slug, threadSlug, server));
    }
  }

  /// Starts a draft, unless the chat on screen is already empty.
  void newChat() {
    if (turns.isEmpty) return;
    _draft = [];
    _draftGo++;
    editing = null;
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

  /// How long a deleted chat can be put back before it is deleted on the server.
  static const undoFor = Duration(seconds: 6);

  /// The chat deleted from the list but not yet on the server, while it can be put back.
  _Deleted? _deleted;
  Timer? _deleteTimer;

  /// Whether [dispose] ran, after which a delete that comes back changes nothing.
  bool _disposed = false;

  /// The name of the chat that [undoDelete] would put back, or null.
  String? get deletedChat => _deleted?.chat.name;

  /// Takes chat [threadSlug] of the workspace on screen out of the list at once, and deletes it
  /// on the server [undoFor] later, unless [undoDelete] puts it back first. Another delete, or
  /// [flushDelete], sends the one waiting at once. The chat on screen gives way to the one
  /// beside it, or a draft.
  Future<void> delete(String threadSlug) async {
    final slug = activeSlug;
    final server = _server;
    if (slug == null || server == null || isAnswering(threadSlug)) return;
    unawaited(flushDelete());
    final was = threadsOf(slug);
    final at = was.indexWhere((t) => t.slug == threadSlug);
    if (at < 0) return;
    final open = activeThread == threadSlug;
    _deleted = _Deleted(
      server: server,
      slug: slug,
      chat: was[at],
      at: at,
      turns: _turns[threadSlug],
      open: open,
    );
    final list = [...was]..removeAt(at);
    _threads[slug] = list;
    _turns.remove(threadSlug);
    _deleteTimer = Timer(undoFor, () => unawaited(flushDelete()));
    if (open) {
      _draft = [];
      await this.open(
        list.isEmpty ? null : list[at.clamp(0, list.length - 1)].slug,
      );
    } else {
      notifyListeners();
    }
  }

  /// The chat [delete] took out, which is no longer waiting, or null when none was.
  _Deleted? _takeDeleted() {
    final deleted = _deleted;
    _deleteTimer?.cancel();
    _deleted = null;
    return deleted;
  }

  /// Puts the chat [delete] took out back where it was, and on screen if it was.
  Future<void> undoDelete() async {
    final deleted = _takeDeleted();
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
  Future<void> flushDelete() async {
    final deleted = _takeDeleted();
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
  /// is a draft. A message that [resetsChat] clears the chat instead. True when the message was
  /// taken; false when nothing was sent, as when the old exchange of an edit could not be
  /// deleted, so the person still has it to send.
  Future<bool> send(
    String message, {
    List<Attachment> attachments = const [],
  }) async {
    final slug = activeSlug;
    final text = message.trim();
    if (slug == null || text.isEmpty || busy || !ready) return false;
    _clearLinkNotice();
    if (resetsChat(text, _presets)) {
      await _reset(slug);
      return true;
    }
    if (editing case final edited?) {
      final at = this.turns.indexOf(edited);
      if (at >= 0) {
        if (!await _dropFrom(edited.chatId)) return false;
        _setTurns(this.turns.sublist(0, at));
      }
      editing = null;
    }
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
      answer,
      _api.streamChat(slug, thread, text, attachments: attachments),
      user: user,
      sent: (text: text, attachments: attachments),
    );
    return true;
  }

  /// Reads [events] into [answer], the answer [running] is, until it ends or fails. [user] is
  /// the question just sent, whose id the server's closing event also carries, and [sent] its
  /// message as typed; both null for an answer found again, whose chat is read once it ends.
  void _follow(
    _Running running,
    Turn answer,
    Stream<ChatEvent> events, {
    Turn? user,
    ({String text, List<Attachment> attachments})? sent,
  }) {
    final slug = running.slug;
    final thread = running.thread!;
    running.stream = events.listen(
      (event) {
        switch (event) {
          case TextChunk(:final text):
            answer._grow(text);
          case StatusChunk(:final text, :final tool):
            answer._setStatus(text, tool: tool);
          case WholeAnswer(:final text):
            answer._replace(text);
          case ChatDone(
            :final citations,
            :final files,
            :final metrics,
            :final chatId,
          ):
            answer
              ..citations = citations
              ..files = files
              ..metrics = metrics
              ..chatId = chatId;
            user?.chatId = chatId;
        }
      },
      onError: (Object error) {
        if ((error, user, sent) case (
          AlreadyAnswering(),
          final user?,
          final sent?,
        )) {
          _refuse(running, user, sent);
          return;
        }
        if (error is AnswerStillRunning) answer.stillRunning = true;
        _finish(
          running,
          error: error is ApiException ? error.message : '$error',
        );
      },
      onDone: () {
        _finish(running);
        if (user == null) {
          unawaited(_readAgain(slug, thread, answer));
        } else if (answer.chatId == null && signedIn) {
          unawaited(_learnIds(slug, thread, user, answer));
        }
      },
      cancelOnError: true,
    );
  }

  /// Takes back the message [running] was to answer, which the relay refused because its chat
  /// already has an answer running, maybe started on another device: the question [user] leaves
  /// the chat with the answer, [sent] waits for the composer to take it back, and the answer
  /// already running is followed in their place, so Stop stops it and a message held for its end
  /// goes when it ends.
  void _refuse(
    _Running running,
    Turn user,
    ({String text, List<Attachment> attachments}) sent,
  ) {
    if (!_runs.remove(running)) return;
    final slug = running.slug;
    final thread = running.thread!;
    if (_turns[thread] case final turns?) {
      _turns[thread] = [
        for (final turn in turns)
          if (!identical(turn, user) && !identical(turn, running.answer)) turn,
      ];
    }
    _refusedIn.add(thread);
    _refused[thread] = (text: sent.text, attachments: sent.attachments);
    notifyListeners();
    final server = _server;
    unawaited(
      _rejoin(slug, thread, server, elsewhere: true).then((_) {
        // Nothing found running: it ended meanwhile, and the message can simply be sent.
        if (_disposed || _server != server || !_refusedIn.contains(thread)) {
          return;
        }
        if (isAnswering(thread)) return;
        _refusedIn.remove(thread);
        notifyListeners();
      }),
    );
  }

  /// Follows the answer the relay is still writing in chat [thread], if there is one that this
  /// run of the app did not start, as when it was closed meanwhile or lost touch with it, or when
  /// it was started [elsewhere], on another device. The answer the app let go of, which the chat
  /// shows as unfinished, is the one followed again. Only a chat whose history was read, and that
  /// nothing changed while the relay was asked: a message sent, a clear or a read meanwhile is
  /// newer than what the relay listed. Another chat answering does not keep it from being
  /// followed, as the relay already runs it.
  Future<void> _rejoin(
    String slug,
    String thread,
    Connection? server, {
    bool elsewhere = false,
  }) async {
    final shown = _turns[thread];
    if (shown == null || _following(thread)) return;
    final RejoinedAnswer? found;
    try {
      found = await _api.rejoinChat(slug, thread);
    } on ApiException {
      return;
    }
    if (found == null ||
        _disposed ||
        _server != server ||
        _following(thread) ||
        activeSlug != slug ||
        activeThread != thread ||
        !identical(_turns[thread], shown)) {
      return;
    }
    final turns = [...shown];
    if (turns.lastOrNull case final last?
        when last.role == Role.assistant && last.unfinished) {
      turns.removeLast();
    }
    if (found.question case final question?
        when turns.lastOrNull?.role != Role.user ||
            turns.last.text != question) {
      turns.add(Turn.user(question));
    }
    final answer = Turn.answer()..rejoined = !elsewhere;
    _turns[thread] = [...turns, answer];
    final running = _Running(answer, slug)..thread = thread;
    _runs.add(running);
    editing = null;
    _sends++;
    notifyListeners();
    _follow(running, answer, found.events);
  }

  /// Whether chat [thread] is followed already, or is being cleared or its exchanges dropped,
  /// which a run found meanwhile would race.
  bool _following(String thread) => isAnswering(thread) || _changing(thread);

  /// Reads chat [thread] once [answer], found again, has ended, so the turns on screen are the
  /// saved ones, with their ids. [answer] stays the same turn and takes what the server saved,
  /// so what follows it, as Read aloud does, keeps it. Keeps what is shown when the server has
  /// not saved it yet, or when the chat changed or a question is being edited meanwhile.
  Future<void> _readAgain(String slug, String thread, Turn answer) async {
    final server = _server;
    final shown = _turns[thread];
    if (shown == null || !identical(shown.lastOrNull, answer)) return;
    try {
      final history = await _api.history(slug, thread);
      if (_disposed ||
          _server != server ||
          !identical(_turns[thread], shown) ||
          (editing != null && shown.contains(editing))) {
        return;
      }
      // The answer is saved once it ends; until the history is as long as the turns shown, it
      // does not have it yet.
      if (history.lastOrNull case final saved?
          when saved.role == Role.assistant && history.length >= shown.length) {
        answer
          ..text = saved.text
          ..citations = saved.citations
          ..files = saved.files
          ..metrics = saved.metrics
          ..chatId = saved.chatId
          ..feedback = saved.feedback
          ..rejoined = false
          ..notifyListeners();
        _turns[thread] = [
          for (final m in history.take(history.length - 1)) Turn.saved(m),
          answer,
        ];
        notifyListeners();
      }
    } on ApiException {
      // The turns on screen are the answer; nothing else depends on the read.
    }
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
        turns[turns.length - 2].role == Role.user &&
        turns[turns.length - 2].attachments.isEmpty;
  }

  /// Asks the chat's last question again, in place of its answer. While [signedIn] the old
  /// exchange is deleted on the server first, its id read from the chat's history when the
  /// answer did not say it; otherwise, or when the history does not show it, the server keeps it
  /// too, and it shows again when the chat is next read.
  Future<void> retry() async {
    if (!canRetry) return;
    // Retry replaces the last exchange only; a question being edited stays as it was.
    if (editing != null) {
      editing = null;
      notifyListeners();
    }
    final turns = this.turns;
    final question = turns[turns.length - 2];
    if ((activeSlug, activeThread) case (final slug?, final thread?)
        when signedIn && question.chatId == null && turns.last.chatId == null) {
      await _learnIds(slug, thread, question, turns.last);
      if (!identical(this.turns, turns) || !canRetry) return;
    }
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
    _droppingIn.add(thread);
    notifyListeners();
    try {
      await _api.dropFrom(slug, thread, chatId);
      if (_server == server && activeSlug == slug && activeThread == thread) {
        return true;
      }
      // The person moved on meanwhile: the chat is read afresh when it is next opened.
      if (_server == server) _turns.remove(thread);
      return false;
    } on ApiException catch (error) {
      if (_server == server) {
        problem = Notice('Could not replace the old exchange', error.message);
      }
      return false;
    } finally {
      // A new server has started afresh, dropping included.
      if (_server == server) {
        _droppingIn.remove(thread);
        notifyListeners();
      }
    }
  }

  /// Clears the history of the chat on screen, on the server and here. A draft has none, so it
  /// is only emptied.
  Future<void> _reset(String slug) async {
    editing = null;
    final thread = activeThread;
    if (thread == null) {
      _draft = [];
      notifyListeners();
      return;
    }
    final server = _server;
    _clearingIn.add(thread);
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
        _clearingIn.remove(thread);
        notifyListeners();
      }
    }
  }

  /// Stops the answer running in the chat on screen, on the server too, keeping what came so far.
  void stop() {
    final running = _here;
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
    if (!_runs.remove(running)) return;
    _refusedIn.remove(running.thread);
    if ((running.thread, running.nameAs) case (final thread?, final message?)
        when !_named.contains(thread)) {
      unawaited(_nameAfter(running.slug, thread, message));
    }
    if (error == null && !running.answer.stopped) {
      _finished = running.answer;
      if (running.thread case final thread?
          when thread != activeThread || running.slug != activeSlug) {
        _ready[thread] = running.slug;
      }
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

  /// Takes the ids of the exchange [user] and [answer] from the chat's history, for an answer
  /// whose closing chunk did not say them, as an agent's does not. A wrong id would make Retry or
  /// an edit delete other exchanges, so the ids are taken only while the exchange is still the
  /// last in its chat and finished, and only from a last history entry that asks the same
  /// question under an id newer than every id the chat already has.
  Future<void> _learnIds(
    String slug,
    String thread,
    Turn user,
    Turn answer,
  ) async {
    final server = _server;
    final List<ChatMessage> history;
    try {
      history = await _api.history(slug, thread);
    } on ApiException {
      return;
    }
    final turns = _turns[thread];
    if (_server != server ||
        turns == null ||
        turns.length < 2 ||
        !identical(turns.last, answer) ||
        !identical(turns[turns.length - 2], user) ||
        answer.unfinished ||
        answer.chatId != null ||
        isAnswering(thread)) {
      return;
    }
    if (history case [..., final asked, final said]
        when asked.role == Role.user &&
            said.role == Role.assistant &&
            said.chatId != null &&
            asked.chatId == said.chatId &&
            asked.text.trim() == user.text.trim()) {
      final id = said.chatId!;
      if (turns.any((t) => t.chatId != null && t.chatId! >= id)) return;
      answer.chatId = user.chatId = id;
      answer.notifyListeners();
      notifyListeners();
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

  /// The last frame of the image at [url] in an answer, read from this server, or null.
  Uint8List? lastFrame(Uri url) => _images[url]?.frame;

  /// The frames of the image at [url] in an answer, each kept as its [lastFrame]. An image
  /// whose last read gave one frame and ended is given again without asking: a card's address
  /// changes with what it shows, and a finished run's card no longer changes. A live one is
  /// read again, so it shows its newest frame. Fails with [ApiException].
  Stream<Uint8List> imageFrames(Uri url) {
    final known = _images[url];
    if (known != null && known.whole) return Stream.value(known.frame);
    final server = _server;
    var frames = 0;
    Uint8List? previous;
    return _api
        .answerImage(url)
        .transform(
          StreamTransformer.fromHandlers(
            handleData: (frame, sink) {
              if (_server != server) return;
              // Counted before the copy is dropped, so a live card that ended after its first
              // frame and the copy is not taken for an image that will not change.
              frames++;
              // A live card sends a still frame again so a browser draws it at once; the copy
              // would only be decoded again.
              if (previous != null && listEquals(previous, frame)) return;
              previous = frame;
              _images[url] = (frame: frame, whole: false);
              sink.add(frame);
            },
            handleDone: (sink) {
              if (_server == server && frames == 1) {
                _images[url] = (frame: _images[url]!.frame, whole: true);
              }
              sink.close();
            },
          ),
        );
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
