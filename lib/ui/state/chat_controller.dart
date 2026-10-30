import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';

import '../../core/chat.dart';
import '../../core/connection.dart';
import '../../core/ports.dart';
import '../../core/prefs.dart';
import '../../core/shortcuts.dart';
import '../../core/server_models.dart';
import '../../core/users.dart';
import 'answer_bytes.dart';
import 'answer_waits.dart';
import 'fleeting.dart';
import 'follows_server.dart';
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
  _Running(this.question, this.answer, this.slug, this.shortcutUse);

  final Turn question;
  final Turn answer;

  /// The workspace the answer runs in.
  final String slug;
  String? thread;
  StreamSubscription<ChatEvent>? stream;

  /// The message a chat this answer's message made is named after when the answer ends, however
  /// it ends; null for a chat that already had a name.
  String? nameAs;

  final ShortcutUse? shortcutUse;
}

/// A message waiting in a chat to be sent when the answer before it ends ([sendWhenDone]).
class OnDeck {
  OnDeck(
    this.text, {
    this.shortcutUse,
    this.attachments = const [],
    this.mode,
    this.lost = const [],
  });

  final String text;
  final ShortcutUse? shortcutUse;

  /// The files that go with it.
  final List<Attachment> attachments;

  /// The workspace's chat mode when it was written, from which [modeForFiles] picks the mode
  /// its files go in.
  final ChatMode? mode;

  /// The names of the files it was written with that were not kept when the app closed: it
  /// goes without them.
  final List<String> lost;

  /// [attachments] as a sent question shows them.
  late final List<SentFile> files = [for (final a in attachments) a.sent];
}

/// The messages waiting in a chat: its workspace, the messages in the order they go, and
/// whether they are held, as after the answer before them stopped or failed, until the person
/// resumes them or sends another message.
typedef _Deck = ({String slug, List<OnDeck> next, bool held});

/// The workspaces and their chats, the chat on screen, and the answers running.
///
/// One answer runs at a time in each chat; chats of one workspace answer at once, since
/// AnythingLLM keeps each run's history and saved answer by its thread.
///
/// A chat not yet asked anything is a draft: it lives only here until its first message, which
/// makes the thread on the server. Each workspace also has its Main chat, which is in no thread:
/// it is kept wherever a thread is, under [mainChatOf] the workspace's slug, and goes to the
/// server as no thread ([threadOnServer]). Everything it knows is about the [server] in use; a
/// new server starts it afresh.
class ChatController extends ChangeNotifier with FollowsServer {
  ChatController(this._api, SettingsController settings, this._prefs) {
    followServer(settings);
    unawaited(_prefs.useServer(server?.baseUrl));
  }

  final AnythingLlmApi _api;
  final PrefsController _prefs;

  List<Workspace> workspaces = const [];

  /// Each workspace's chats, newest last, by workspace slug.
  final Map<String, List<Thread>> _threads = {};

  /// How many documents each workspace holds, for the ones read so far.
  final Map<String, int> docCounts = {};

  String? activeSlug;

  /// The chat on screen: a thread's slug, the workspace's [mainChatOf], or null for a draft.
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

  /// The shortcut a saved question was sent with on this device, if it was one.
  ShortcutUse? _useOf(String slug, String thread, Role role, int? chatId) =>
      role == Role.user && chatId != null
      ? _prefs.shortcutUse(slug, thread, chatId)
      : null;

  /// The answers whose connection dropped, read for until the server saved them.
  late final waits = AnswerWaits(
    _api,
    turnsOf: (thread) => _turns[thread],
    saved: (slug, thread, saved) {
      _learnFrom(thread, saved.map((t) => t.chatId));
      for (final turn in saved) {
        turn.shortcutUse = _useOf(slug, thread, turn.role, turn.chatId);
      }
      _turns[thread] = _withUnsent(thread, saved);
      _markFinished(saved.last, slug, thread);
    },
    changed: (thread) {
      _holdIfCut(thread);
      _sendOnDeck();
      notifyListeners();
    },
  );

  /// Whether an answer is running or [Turn.waiting] anywhere, which the app keeps alive for.
  bool get working => _runs.isNotEmpty || waits.any;

  /// The workspace of an answer running or waiting, for the note that keeps the app alive.
  String? get workingIn => _runs.firstOrNull?.slug ?? waits.firstSlug;

  /// The answers running, at most one in each chat.
  final _runs = <_Running>[];

  /// The messages waiting in each chat, by chat. Each list is replaced, never changed, as the
  /// turns are. Every change is kept in the prefs, from which a chat opened after the app
  /// closed takes its messages back, held ([_restoreDeck]).
  final _onDeck = <String, _Deck>{};

  /// The messages waiting in the chat on screen, first to go first.
  List<OnDeck> get onDeck => _onDeck[activeThread]?.next ?? const [];

  /// Whether the messages waiting in the chat on screen are held: the answer before them
  /// stopped or failed, or the app closed while they waited. [resumeOnDeck] sends them on, and
  /// so does a message sent meanwhile once its answer ends.
  bool get onDeckHeld => _onDeck[activeThread]?.held ?? false;

  /// Whether [sendWhenDone] can take a message: an answer runs in the chat on screen, whose
  /// thread is made, or messages wait there that are not held.
  bool get canSendWhenDone =>
      activeThread != null && (answeringHere || _queued);

  /// Whether messages wait in the chat on screen, not held, held back by [_sendOnDeck]: one
  /// sent now would go ahead of them, so it joins them instead.
  bool get _queued => _onDeck.containsKey(activeThread) && !onDeckHeld;

  /// Puts [message], with [attachments], at the end of the messages waiting in the chat on
  /// screen. Each is sent in turn, when the answer before it ends, while another chat shows or
  /// the app is out of sight too, until an answer stops or fails. [mode] is the workspace's
  /// chat mode, as [send] takes it. True when it was taken.
  bool sendWhenDone(
    String message, {
    ShortcutUse? shortcutUse,
    List<Attachment> attachments = const [],
    ChatMode? mode,
  }) {
    final slug = activeSlug;
    final thread = activeThread;
    final text = message.trim();
    if (slug == null || thread == null || text.isEmpty || !canSendWhenDone) {
      return false;
    }
    _setDeck(thread, slug, [
      ...onDeck,
      OnDeck(
        text,
        shortcutUse: shortcutUse,
        attachments: attachments,
        mode: mode,
      ),
    ]);
    notifyListeners();
    return true;
  }

  /// Takes [item] out of the messages waiting in the chat on screen, and says whether it was
  /// there.
  bool dropOnDeck(OnDeck item) {
    final thread = activeThread;
    final deck = _onDeck[thread];
    if (thread == null ||
        deck == null ||
        !deck.next.any((o) => identical(o, item))) {
      return false;
    }
    _setDeck(thread, deck.slug, [
      for (final o in deck.next)
        if (!identical(o, item)) o,
    ]);
    notifyListeners();
    return true;
  }

  /// The messages [clearOnDeck] took out, while [undoClearOnDeck] can put them back: until the
  /// toast is closed ([closeClearedOnDeck]), another toast takes its place, or another chat
  /// shows.
  final _cleared = Fleeting<({String thread, _Deck deck})>.held();

  /// How many messages [undoClearOnDeck] would put back, or null.
  int? get clearedOnDeck => _cleared.value?.deck.next.length;

  /// Takes every message waiting in the chat on screen out at once. [undoClearOnDeck] puts them
  /// back while its toast shows. It takes the place of a deleted chat's toast, whose delete
  /// goes now.
  void clearOnDeck() {
    final thread = activeThread;
    final deck = _onDeck[thread];
    if (thread == null || deck == null) return;
    unawaited(flushDelete());
    _cleared.show((thread: thread, deck: deck));
    _setDeck(thread, deck.slug, const []);
    notifyListeners();
  }

  /// Puts back what [clearOnDeck] took out, ahead of any message written since, in its chat
  /// unless that chat is gone.
  void undoClearOnDeck() {
    final cleared = _cleared.take();
    if (cleared == null) return;
    final (:thread, :deck) = cleared;
    if (_has(deck.slug, thread)) {
      final now = _onDeck[thread];
      _setDeck(thread, deck.slug, [
        ...deck.next,
        ...?now?.next,
      ], held: now?.held ?? deck.held);
      _sendOnDeck();
    }
    notifyListeners();
  }

  /// Closes the toast of what [clearOnDeck] took out: they are gone for good.
  void closeClearedOnDeck() {
    if (_cleared.take() == null) return;
    notifyListeners();
  }

  /// Sends on the messages held in the chat on screen, the first at once when the chat can
  /// take it.
  void resumeOnDeck() {
    if (activeThread case final thread?) {
      _holdDeck(thread, false);
      _sendOnDeck();
      notifyListeners();
    }
  }

  /// Holds the messages waiting in chat [thread], or lets them go on. Whether they are held is
  /// not kept in the prefs.
  void _holdDeck(String thread, bool held) {
    if (_onDeck[thread] case final deck? when deck.held != held) {
      _onDeck[thread] = (slug: deck.slug, next: deck.next, held: held);
    }
  }

  /// Holds the messages waiting in chat [thread] when the answer before them stopped, failed
  /// or was not sent, for the person to resume.
  void _holdIfCut(String thread) {
    final last = _turns[thread]?.lastOrNull;
    if (last != null && ((last.unfinished && !last.waiting) || last.notSent)) {
      _holdDeck(thread, true);
    }
  }

  /// Keeps [next] as the messages waiting in chat [thread] of workspace [slug], or none, [held]
  /// or, by default, as held as they were, in the prefs too.
  void _setDeck(String thread, String slug, List<OnDeck> next, {bool? held}) {
    if (next.isEmpty) {
      _onDeck.remove(thread);
    } else {
      _onDeck[thread] = (
        slug: slug,
        next: next,
        held: held ?? _onDeck[thread]?.held ?? false,
      );
    }
    unawaited(
      _prefs.setOnDeck(slug, thread, [
        for (final o in next)
          SavedOnDeck(
            o.text,
            shortcutUse: o.shortcutUse,
            files: [...o.lost, for (final a in o.attachments) a.name],
          ),
      ]),
    );
  }

  /// Takes back the messages kept waiting in chat [thread] of workspace [slug] when the app
  /// closed, held, since the answer before them ended out of sight. Their files were not kept.
  void _restoreDeck(String slug, String thread) {
    if (_onDeck.containsKey(thread)) return;
    final saved = _prefs.onDeckIn(slug, thread);
    if (saved.isEmpty) return;
    _onDeck[thread] = (
      slug: slug,
      next: [
        for (final m in saved)
          OnDeck(m.text, shortcutUse: m.shortcutUse, lost: m.files),
      ],
      held: true,
    );
  }

  /// Whether chat [thread] can take a waiting message now: nothing runs, is waited for or
  /// clears there, and its turns are read.
  bool _canTakeOnDeck(String thread) =>
      _turns.containsKey(thread) &&
      !isAnswering(thread) &&
      !waits.has(thread) &&
      !_clearing.contains(thread);

  /// Sends the first message waiting in each chat that can take one and is not held, unless
  /// [refresh] is reading the chats again.
  void _sendOnDeck() {
    if (_refreshing) return;
    for (final MapEntry(key: thread, value: deck) in [..._onDeck.entries]) {
      if (!deck.held && _canTakeOnDeck(thread)) _sendFirst(thread, deck);
    }
  }

  /// Sends the first of [deck], the messages waiting in chat [thread], with its files.
  void _sendFirst(String thread, _Deck deck) {
    final first = deck.next.first;
    _setDeck(thread, deck.slug, deck.next.sublist(1));
    final user = Turn.user(
      first.text,
      shortcutUse: first.shortcutUse,
      attachments: first.files,
    );
    final answer = Turn.answer();
    _turns[thread] = [..._turns[thread]!, user, answer];
    final running = _Running(user, answer, deck.slug, first.shortcutUse)
      ..thread = thread;
    _runs.add(running);
    if (thread == activeThread) _sends++;
    _follow(
      running,
      _api.streamChat(
        deck.slug,
        threadOnServer(thread),
        first.text,
        attachments: first.attachments,
        mode: modeForFiles(first.mode, first.attachments),
        userId: _prefs.chosenUser?.id,
      ),
    );
  }

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

  /// The [problem] a failed [load] left, which the unreachable banner says in its own words.
  Notice? _readNotice;

  /// The [problem] to show under the header: none while it is [load]'s own failure and the
  /// server is [unreachable], since the banner says it.
  Notice? get notice =>
      unreachable.value && identical(problem, _readNotice) ? null : problem;

  /// Why a link in an answer did not open. It stays until it is closed ([closeLinkNotice]), or
  /// the next message is sent or chat opened.
  Notice? get linkNotice => _link.value;

  final _link = Fleeting<Notice>.held();

  /// Puts away why a link did not open.
  void closeLinkNotice() {
    if (_link.take() == null) return;
    notifyListeners();
  }

  /// The files and images answers show, read once per server.
  late final bytes = AnswerBytes(_api, report: report);

  Workspace? get active => workspaceOf(activeSlug);

  /// The workspace [slug] names, or null while none does.
  Workspace? workspaceOf(String? slug) =>
      workspaces.where((w) => w.slug == slug).firstOrNull;

  /// Workspace [slug]'s threads, oldest made first. Its Main chat is in none.
  List<Thread> threadsOf(String slug) => _threads[slug] ?? const [];

  /// Whether workspace [slug] has chat [chat]: its Main chat, or one of its threads.
  bool _has(String slug, String chat) =>
      chat == mainChatOf(slug) || threadsOf(slug).any((t) => t.slug == chat);

  /// The thread on screen, or null for a draft and for Main chat, which has no sheet.
  Thread? get thread => activeSlug == null
      ? null
      : threadsOf(activeSlug!).where((t) => t.slug == activeThread).firstOrNull;

  /// Whether the chat on screen is its workspace's Main chat.
  bool get onMainChat => isMainChat(activeThread);

  String get title => onMainChat ? mainChatName : thread?.name ?? newChatName;

  /// The name of chat [chat] of workspace [slug], or null when it has none, as a thread gone.
  String? nameOf(String slug, String chat) => isMainChat(chat)
      ? mainChatName
      : threadsOf(slug).where((t) => t.slug == chat).firstOrNull?.name;

  /// The turns of the chat on screen. A list handed out here is never changed afterwards: every
  /// change sets a new list, since the view may still be drawing from the old one.
  List<Turn> get turns =>
      activeThread == null ? _draft : (_turns[activeThread] ?? const []);

  /// Whether the chat on screen can take no message now: it answers, messages wait there that
  /// are not held, or its history is being cleared.
  bool get busy => answeringHere || _queued || _clearing.contains(activeThread);

  /// The chats whose history is being cleared on the server.
  final _clearing = <String>{};

  /// Whether the chat on screen has a history [reset] can clear: it is a chat, not a draft, it
  /// is read and nothing holds it.
  bool get canReset => activeThread != null && ready && !busy;

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

  /// Whether [refresh] is reading the server again.
  bool get refreshing => _refreshing;
  bool _refreshing = false;

  /// Reads the workspaces and the chat on screen again, for when the connection dropped and
  /// what shows may be stale or stuck. An answer still running in this chat is let go of first,
  /// not stopped: the server may finish it, and it shows when the chat is read again. A chat
  /// deleted on the server gives way to its workspace's newest chat.
  Future<void> refresh() async {
    if (server == null || _refreshing) return;
    _refreshing = true;
    // A draft's first message whose chat is still being made has no answer yet to let go of.
    if (_here case final running? when running.stream != null) {
      unawaited(running.stream?.cancel());
      _finish(
        running,
        error:
            'Let go of this answer to read the chat again. The server may still finish '
            'it; refresh again later to see it.',
        letGo: true,
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
          !_has(slug, thread)) {
        _turns.remove(thread);
        if (_onDeck.containsKey(thread)) _setDeck(thread, slug, const []);
        await select(slug);
      } else {
        await open(thread, again: true);
      }
    } finally {
      _refreshing = false;
      // What the chat holds once read again says whether its waiting messages go on.
      if (thread != null) _holdIfCut(thread);
      _sendOnDeck();
      notifyListeners();
    }
  }

  /// Whether a chat of workspace [slug] is answering, a draft whose chat is being made included.
  bool answeringIn(String slug) => _runs.any((r) => r.slug == slug);

  /// Whether a workspace is open and no chat of it is answering ([answeringIn]).
  bool get activeIdle => activeSlug != null && !answeringIn(activeSlug!);

  /// Whether the message box takes words, files and dictation: the chat on screen can take a
  /// message now, or one to send when its answer ends.
  bool get takesInput => !busy || canSendWhenDone;

  /// Whether [text] can be sent in the chat on screen: a workspace is open, nothing holds the
  /// chat ([busy]), it is [ready], and there is something to send.
  bool canSend(String text) =>
      active != null && !busy && ready && text.trim().isNotEmpty;

  @override
  void dispose() {
    // The last chance to send a delete still waiting to be undone.
    unawaited(flushDelete());
    _disposed = true;
    for (final running in _runs) {
      running.stream?.cancel();
    }
    waits.clear();
    _link.take();
    _cleared.take();
    unreachable.dispose();
    super.dispose();
  }

  /// A delete still waiting to be undone goes to the server it was made on.
  @override
  void leavingServer() => unawaited(flushDelete());

  @override
  void serverChanged(_) {
    unawaited(_prefs.useServer(server?.baseUrl));
    for (final running in _runs) {
      running.stream?.cancel();
    }
    _runs.clear();
    waits.clear();
    _forComposer.clear();
    _onDeck.clear();
    _cleared.take();
    workspaces = const [];
    _threads.clear();
    _turns.clear();
    _newest.clear();
    _madeAt.clear();
    _clearing.clear();
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
    if (server != null) unawaited(load());
  }

  /// The title of the [problem] a failed [load] leaves.
  static const _readFailed = 'Could not read the workspaces';

  /// Reads the workspaces and their chats, keeping the one on screen when it still exists.
  Future<void> load() async {
    final at = here;
    if (at.server == null) return;
    loading = true;
    notifyListeners();
    var failed = true;
    final asked = _made;
    await _try(_readFailed, () async {
      var read = await _api.workspaces();
      if (_narrowedFor case final user?) read = await _openTo(user, read);
      if (!at.current) return;
      failed = false;
      workspaces = read;
      final before = {..._threads};
      _threads
        ..clear()
        ..addAll({
          for (final w in workspaces) w.slug: [...w.threads],
        });
      // A chat made, or answering, while the read was away may be missing from it.
      for (final MapEntry(key: slug, value: list) in before.entries) {
        if (_threads[slug] case final now?) {
          for (final t in list) {
            if (now.any((n) => n.slug == t.slug)) continue;
            if (isAnswering(t.slug) || (_madeAt[t.slug] ?? 0) > asked) {
              now.add(t);
            }
          }
        }
      }
      // A chat deleted in the list but not yet on the server is still in the server's list.
      if (_deleted.value case final deleted?
          when _threads.containsKey(deleted.slug)) {
        _threads[deleted.slug] = [
          for (final t in _threads[deleted.slug]!)
            if (t.slug != deleted.chat.slug) t,
        ];
      }
    });
    if (!at.current) return;
    loading = false;
    _readNotice = failed ? problem : null;
    unreachable.value = failed;
    (String, String)? tapped;
    if (!failed) {
      tapped = _tapped;
      _tapped = null;
    }
    if (tapped case (final slug, final thread)
        when workspaces.any((w) => w.slug == slug)) {
      await select(slug, thread: _kept(slug, thread));
    } else if (active == null) {
      final (slug, thread) = _startChat;
      await select(slug, thread: thread);
    } else {
      notifyListeners();
    }
    unawaited(_countDocs());
  }

  /// The user chosen on a multi-user server ([PrefsController.chosenUser]) when the workspaces
  /// are narrowed to theirs: one who is not an admin or a manager. Null shows every workspace.
  ServerUser? get _narrowedFor => switch (_prefs.chosenUser) {
    final user? when !user.opensEvery => user,
    _ => null,
  };

  /// [all] with only the workspaces [user] opens ([ServerUser.opens]), each read at once. One
  /// whose users cannot be read stays, as every workspace does with no one chosen: the key opens
  /// them all whoever is chosen, so one too many hides nothing.
  Future<List<Workspace>> _openTo(ServerUser user, List<Workspace> all) async {
    Future<bool> opens(Workspace workspace) async {
      final id = workspace.id;
      if (id == null) return true;
      try {
        return user.opens(await _api.workspaceUsers(id));
      } on ApiException {
        return true;
      }
    }

    final open = await Future.wait([for (final w in all) opens(w)]);
    return [
      for (final (i, w) in all.indexed)
        if (open[i]) w,
    ];
  }

  /// How many chats this controller has made on the server, and by chat when each was made, so a
  /// [load] that began earlier does not forget one.
  int _made = 0;
  final _madeAt = <String, int>{};

  /// The chat a tapped notification asked for before the workspaces were read, which [load]
  /// opens in place of the last chat.
  (String, String)? _tapped;

  /// Opens chat [thread] of workspace [slug], as a tapped notification asks. Before the
  /// workspaces are read, as when the tap started the app, [load] opens it once they are. A
  /// workspace gone since opens nothing, and a chat gone since gives way to its workspace's
  /// newest.
  Future<void> openTapped(String slug, String thread) {
    // No server means no workspaces: a new one empties them.
    if (workspaces.isEmpty) {
      _tapped = (slug, thread);
      return Future.value();
    }
    if (!workspaces.any((w) => w.slug == slug)) return Future.value();
    return select(slug, thread: _kept(slug, thread));
  }

  /// [thread] while workspace [slug] still has it, else null. Main chat is always there.
  String? _kept(String slug, String thread) =>
      thread == mainChatOf(slug) || threadsOf(slug).any((t) => t.slug == thread)
      ? thread
      : null;

  /// Asks each workspace how many documents it holds, all at once. Best effort: a count that
  /// cannot be read is left out. Sources reports the active workspace's own count.
  Future<void> _countDocs() async {
    final at = here;
    Future<void> count(String slug) async {
      try {
        final workspace = await _api.workspace(slug);
        if (!at.current) return;
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
    if (!at.current) return;
    notifyListeners();
  }

  /// [workspaces] in the order the person arranged, new ones after in the server's order.
  List<Workspace> get orderedWorkspaces =>
      _prefs.prefs.inOrder(workspaces, (w) => w.slug);

  /// The first workspace in the order the person arranged, or null when there is none.
  String? get _firstSlug => orderedWorkspaces.firstOrNull?.slug;

  /// The workspace and chat to open first: the last on screen while the workspace exists, on
  /// its newest chat when that chat is gone; otherwise [_firstSlug] on its newest chat.
  (String?, String?) get _startChat {
    final last = _prefs.prefs.lastChat;
    if (last == null ||
        last.server != server?.baseUrl ||
        !workspaces.any((w) => w.slug == last.slug)) {
      return (_firstSlug, null);
    }
    final chat = last.thread;
    return (last.slug, chat != null && _has(last.slug, chat) ? chat : null);
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

  /// Shows workspace [slug] on chat [thread], or on its newest thread, or a draft when it has
  /// none.
  Future<void> select(String? slug, {String? thread}) async {
    _leaving(thread);
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
    if (threadSlug != null && threadSlug != activeThread) _leaving(threadSlug);
    activeThread = threadSlug;
    if (threadSlug != null) {
      _ready.remove(threadSlug);
      if (activeSlug case final slug?) _restoreDeck(slug, threadSlug);
    }
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
    final at = here;
    final shown = known;
    final newest = _newest[threadSlug];
    await _try('Could not read the chat', () async {
      final history = await _api.history(slug, threadOnServer(threadSlug));
      if (!at.current) return;
      // A message sent or an answer settled while the read was away says more than it does.
      if (!identical(_turns[threadSlug], shown) ||
          _newest[threadSlug] != newest) {
        return;
      }
      _learnFrom(threadSlug, history.map((m) => m.chatId));
      if (isAnswering(threadSlug)) return;
      // An answer the server is still writing is saved only once it ends; until then the chat
      // keeps what it showed, and stays unfinished so it is read again. A finished chat read
      // [again] takes what the server has, though it was cleared or cut short elsewhere.
      if (known != null &&
          known.lastOrNull?.unfinished == true &&
          history.length < known.where((t) => !t.notSent).length) {
        return;
      }
      _turns[threadSlug] = _withUnsent(threadSlug, [
        for (final m in history)
          Turn.saved(
            m,
            shortcutUse: _useOf(slug, threadSlug, m.role, m.chatId),
          ),
      ]);
    });
  }

  /// [saved], chat [thread]'s turns as the server has them, followed by its questions the server
  /// never took, which are in no history and stay to be sent again or edited.
  List<Turn> _withUnsent(String thread, List<Turn> saved) => [
    ...saved,
    ...?_turns[thread]?.where((t) => t.notSent),
  ];

  /// Empties the draft, so a send or read meant for the one before leaves it alone.
  /// Another chat is about to show, [thread] or a draft: a deleted chat's toast is done, so its
  /// delete goes, and Clear all's toast for another chat goes with what it took out.
  void _leaving(String? thread) {
    unawaited(flushDelete());
    if (_cleared.value case final cleared? when cleared.thread != thread) {
      _cleared.take();
    }
  }

  void _freshDraft() {
    _draft = [];
    _draftGo++;
  }

  /// Starts a draft, unless the chat on screen is already empty: a draft, or a thread read with
  /// no turns. A chat whose turns are still being read is not empty, and Main chat, empty or not,
  /// gives way to a draft, since what it is asked stays in it.
  void newChat() {
    if (ready && turns.isEmpty && !onMainChat) return;
    _leaving(null);
    _freshDraft();
    activeThread = null;
    _rememberChat();
    notifyListeners();
  }

  /// Makes workspace [name] with [prompt] as its instructions and opens it. An empty prompt is
  /// none, so the server's default applies.
  Future<void> createWorkspace(String name, {String prompt = ''}) {
    final at = here;
    return _try('Could not make the workspace', () async {
      final made = await _api.createWorkspace(
        name.trim(),
        prompt: prompt.trim().isEmpty ? null : prompt,
      );
      if (!at.current) return;
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
    final at = here;
    Workspace? renamed;
    await _try('Could not rename the workspace', () async {
      renamed = await _api.renameWorkspace(slug, clean);
      if (!at.current || renamed!.slug != slug) return;
      workspaces = [
        for (final w in workspaces)
          w.slug == slug ? w.withName(renamed!.name) : w,
      ];
    });
    // Read again outside the rename's own notice, so a failed read stays shown.
    if (renamed case final made? when at.current && made.slug != slug) {
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
    final at = here;
    await _try('Could not delete the workspace', () async {
      await _api.deleteWorkspace(slug);
      if (!at.current) return;
      // A chat waiting to be deleted goes with its workspace: its delete would find none.
      if (_deleted.value?.slug == slug) _deleted.take();
      for (final chat in [
        mainChatOf(slug),
        for (final t in threadsOf(slug)) t.slug,
      ]) {
        _turns.remove(chat);
        _newest.remove(chat);
        _named.remove(chat);
        _onDeck.remove(chat);
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

  /// Renames thread [threadSlug] of the workspace on screen. Main chat keeps its name.
  Future<void> rename(String threadSlug, String name) async {
    final slug = activeSlug;
    final clean = name.trim();
    if (slug == null || clean.isEmpty || isMainChat(threadSlug)) return;
    final at = here;
    await _try('Could not rename the chat', () async {
      await _api.renameThread(slug, threadSlug, clean);
      if (!at.current) return;
      _named.add(threadSlug);
      _replace(slug, Thread(slug: threadSlug, name: clean));
    });
  }

  /// The chat deleted from the list but not yet on the server, while it can be put back: its
  /// toast has no clock, so nothing is deleted before the person is done with it.
  final _deleted = Fleeting<_Deleted>.held();

  /// Whether [dispose] ran, after which a delete that comes back changes nothing.
  bool _disposed = false;

  /// The name of the chat that [undoDelete] would put back, or null.
  String? get deletedChat => _deleted.value?.chat.name;

  /// Takes chat [threadSlug] of the workspace on screen out of the list at once, and deletes it
  /// on the server only once its toast is done: closed ([flushDelete]), replaced by another
  /// delete or Clear all, left for another chat or workspace, another server, the app hiding or
  /// [dispose]. [undoDelete] puts it back before then, and nothing is sent. The chat on screen
  /// gives way to a new chat, a draft in the same workspace. Main chat, in no list
  /// ([threadsOf]), is never deleted.
  Future<void> delete(String threadSlug) async {
    final slug = activeSlug;
    final server = this.server;
    if (slug == null || server == null || isAnswering(threadSlug)) return;
    unawaited(flushDelete());
    _cleared.take();
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
    _newest.remove(threadSlug);
    _onDeck.remove(threadSlug);
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

  /// Deletes on the server, now, the chat [delete] took out, on the server it was on, as its
  /// toast's Close does. A delete the server refuses puts the chat back.
  Future<void> flushDelete() => _send(_deleted.take());

  /// Deletes [deleted] on its server, putting it back when the server refuses.
  Future<void> _send(_Deleted? deleted) async {
    if (deleted == null) return;
    notifyListeners();
    final thread = deleted.chat.slug;
    try {
      await _api.deleteThread(deleted.slug, thread, on: deleted.server);
      if (!_disposed && server == deleted.server) {
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
    if (server != deleted.server) return false;
    final list = [...threadsOf(deleted.slug)];
    if (list.any((t) => t.slug == deleted.chat.slug)) return true;
    list.insert(deleted.at.clamp(0, list.length), deleted.chat);
    _threads[deleted.slug] = list;
    if (deleted.turns case final turns?) _turns[deleted.chat.slug] = turns;
    return true;
  }

  /// Asks [message], with [attachments], in the chat on screen, making its thread first when it
  /// is a draft. [mode] is the workspace's chat mode, from which [modeForFiles] picks the mode
  /// a document is sent in. True when the message was taken.
  Future<bool> send(
    String message, {
    List<Attachment> attachments = const [],
    ShortcutUse? shortcutUse,
    ChatMode? mode,
  }) async {
    if (!canSend(message)) return false;
    final slug = activeSlug!;
    final text = message.trim();
    // Messages held in this chat follow this one, unless its answer stops or fails too.
    if (activeThread case final thread?) _holdDeck(thread, false);
    _link.take();
    final user = Turn.user(
      text,
      shortcutUse: shortcutUse,
      attachments: [for (final a in attachments) a.sent],
    );
    final answer = Turn.answer();
    final turns = [...this.turns, user, answer];
    final running = _Running(user, answer, slug, shortcutUse)
      ..thread = activeThread;
    _runs.add(running);
    final at = here;
    final draftGo = _draftGo;
    _setTurns(turns);
    _sends++;
    notifyListeners();

    var threadSlug = activeThread;
    if (threadSlug == null) {
      try {
        final made = await _api.createThread(
          slug,
          userId: _prefs.chosenUser?.id,
        );
        // A new server has started afresh: the chat belongs to the old one.
        if (!at.current) return true;
        threadSlug = made.slug;
        _madeAt[made.slug] = ++_made;
        _newest[made.slug] = -1;
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
        _finish(running, error: error.message, notSent: true);
        return true;
      }
      // Stopped while the thread was being made: the chat stays and is named, the answer does
      // not run.
      if (!_runs.contains(running)) {
        final made = running.thread!;
        if (!_named.contains(made)) unawaited(_nameAfter(slug, made, text));
        unawaited(_prefs.useChat(slug, made));
        notifyListeners();
        return true;
      }
    }
    final thread = threadSlug;
    _follow(
      running,
      _api.streamChat(
        slug,
        threadOnServer(thread),
        text,
        attachments: attachments,
        mode: modeForFiles(mode, attachments),
        userId: _prefs.chosenUser?.id,
      ),
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
          notSent: error is NotSent,
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

  /// Takes [turn] out of whichever chat holds it, as a new list.
  void _dropTurn(Turn turn) {
    List<Turn> without(List<Turn> turns) => [
      for (final t in turns)
        if (!identical(t, turn)) t,
    ];
    for (final thread in _turns.keys.toList()) {
      if (_turns[thread]!.any((t) => identical(t, turn))) {
        _turns[thread] = without(_turns[thread]!);
      }
    }
    if (_draft.any((t) => identical(t, turn))) _draft = without(_draft);
  }

  /// Whether [sendAgain] can send [question], a [Turn.notSent] one, now: it carried no files,
  /// whose bytes are not kept, and the chat can take a message.
  bool canSendAgain(Turn question) =>
      question.notSent && question.attachments.isEmpty && !busy && ready;

  /// Sends [question], which did not reach the server, again in its place.
  Future<void> sendAgain(Turn question) async {
    if (!canSendAgain(question)) return;
    _dropTurn(question);
    await send(question.text, shortcutUse: question.shortcutUse);
  }

  /// Takes [question], which did not reach the server, out of the chat, to be written again.
  void discard(Turn question) {
    if (!question.notSent) return;
    _dropTurn(question);
    notifyListeners();
  }

  /// Asks the chat's last question again, in place of its answer here. The server keeps the old
  /// exchange too, which shows again when the chat is next read.
  Future<void> retry() async {
    if (!canRetry) return;
    final turns = this.turns;
    final question = turns[turns.length - 2];
    _setTurns(turns.sublist(0, turns.length - 2));
    await send(question.text, shortcutUse: question.shortcutUse);
  }

  /// Clears the history of the chat on screen, on the server and here, so the model starts the
  /// chat afresh. The server keeps the rows hidden and nothing here brings them back. A failure
  /// shows as [problem] and leaves the turns as they were.
  Future<void> reset() async {
    final slug = activeSlug;
    final thread = activeThread;
    if (slug == null || thread == null || !canReset) return;
    final at = here;
    _clearing.add(thread);
    notifyListeners();
    await _try('Could not clear the chat', () async {
      try {
        await _api.resetChat(slug, threadOnServer(thread));
        if (!at.current) return;
        _turns[thread] = [];
        _newest[thread] = -1;
      } finally {
        _clearing.remove(thread);
        // Messages resumed while it cleared go on now.
        _sendOnDeck();
      }
    });
  }

  /// Ends [running], whose connection dropped, without failing it: AnythingLLM may still finish
  /// the answer, so the chat's history is read until it holds it.
  void _wait(_Running running) {
    final thread = running.thread;
    if (thread == null) {
      return _finish(running, error: 'The connection dropped.');
    }
    // Waiting before the run ends, so [working] holds throughout.
    waits.start(running.answer, running.slug, thread, after: _newest[thread]);
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

  /// By chat, the newest exchange the server has saved, when it is known; -1 for a chat with
  /// none. A dropped answer is the first exchange after it ([AnswerWaits.start]).
  final _newest = <String, int>{};

  /// By chat, the history read [_learnNewest] has under way, which only it may take.
  final _learning = <String, Object>{};

  /// Learns chat [thread]'s newest exchange from the [ids] the server gave its history.
  /// It never moves back: a read that is older than what the chat knows keeps what it knows.
  void _learnFrom(String thread, Iterable<int?> ids) => _newest[thread] = max(
    _newest[thread] ?? -1,
    ids.map((id) => id ?? -1).fold(-1, max),
  );

  /// Keeps chat [thread]'s newest exchange as [running]'s answer leaves it. An answer whose
  /// closing chunk named its exchange is the newest. One that ran to its end without, as an
  /// agent's does, is learnt from the history, read once. A stopped or failed one leaves it
  /// unknown, since the server may still save that answer later; a dropped one is waited for.
  void _settle(_Running running, String thread, {String? error}) {
    final answer = running.answer;
    if (answer.waiting) return;
    // A read started for an earlier answer would say less than this one does.
    _learning.remove(thread);
    if (answer.chatId case final id?) {
      _newest[thread] = id;
      return;
    }
    _newest.remove(thread);
    if (error == null && !answer.stopped) {
      unawaited(_learnNewest(running.slug, thread, running.shortcutUse));
    }
  }

  /// Reads chat [thread]'s history for its newest exchange alone, leaving its turns as they are.
  /// That exchange is the answer's, which an agent's closing chunk does not name, so the
  /// [use] of a shortcut its question was sent with is remembered under it.
  Future<void> _learnNewest(
    String slug,
    String thread,
    ShortcutUse? use,
  ) async {
    final at = here;
    final go = _learning[thread] = Object();
    try {
      final history = await _api.history(slug, threadOnServer(thread));
      // Only the latest read counts: an answer that ended meanwhile, as a waiting message
      // sent since, settled the chat afresh.
      if (at.current && identical(_learning[thread], go)) {
        _learnFrom(thread, history.map((m) => m.chatId));
        if (use != null && (_newest[thread] ?? -1) >= 0) {
          unawaited(
            _prefs.rememberShortcutUse(slug, thread, _newest[thread]!, use),
          );
        }
      }
    } on ApiException {
      // Still unknown: a dropped answer then falls back to reading its question.
    } finally {
      if (identical(_learning[thread], go)) _learning.remove(thread);
    }
  }

  /// Records [turn] as the last answer that ran to its end, and marks its chat ready unless it
  /// is the one on screen.
  void _markFinished(Turn turn, String slug, String thread) {
    _finished = (turn: turn, slug: slug, thread: thread);
    if (thread != activeThread || slug != activeSlug) _ready[thread] = slug;
  }

  /// Ends [running], with [error] when it failed, unless it was already stopped or dropped. A
  /// [notSent] question never reached the server: it stays in the chat marked [Turn.notSent],
  /// with no answer under it. An answer [refresh] let go of ([letGo]) is judged once its chat
  /// is read again.
  void _finish(
    _Running running, {
    String? error,
    bool notSent = false,
    bool letGo = false,
  }) {
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
      final chatId = running.answer.chatId;
      if (running.shortcutUse case final use? when chatId != null) {
        unawaited(
          _prefs.rememberShortcutUse(running.slug, thread, chatId, use),
        );
      }
      // A question the server never took leaves its newest exchange as it was.
      if (!notSent) _settle(running, thread, error: error);
    }
    running.answer
      ..streaming = false
      ..status = null
      ..error = error
      ..notifyListeners();
    if (notSent) {
      running.question
        ..notSent = true
        ..notifyListeners();
      _dropTurn(running.answer);
    }
    // Before telling anyone, so [working] holds while a chat has messages waiting. The answer
    // [refresh] lets go of is judged once the chat is read again; any other that ends while it
    // reads is judged now.
    if (running.thread case final thread? when !letGo) {
      _holdIfCut(thread);
    }
    _sendOnDeck();
    notifyListeners();
  }

  /// Names a new chat after its first message, unless it was renamed meanwhile.
  Future<void> _nameAfter(String slug, String thread, String message) async {
    final name = defaultTitle(message);
    final at = here;
    try {
      await _api.renameThread(slug, thread, name);
      if (at.current && !_named.contains(thread)) {
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

  /// Shows why a link in an answer did not open, until it is closed.
  void reportLink(String title, String text) {
    _link.show(Notice(title, text));
    notifyListeners();
  }

  /// Runs [op], showing its failure as a [Notice] titled [failTitle]. A new server meanwhile has
  /// started afresh, so neither its success nor its failure is shown.
  Future<void> _try(String failTitle, Future<void> Function() op) async {
    final at = here;
    try {
      await op();
      if (!at.current) return;
      problem = null;
    } on ApiException catch (error) {
      if (!at.current) return;
      problem = Notice(failTitle, error.message);
    }
    notifyListeners();
  }
}
