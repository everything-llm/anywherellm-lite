import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';

import '../../core/asks.dart';
import '../../core/ports.dart';
import '../../core/toolkit.dart';
import '../chat/background_work.dart';
import 'chat_controller.dart';
import 'notice.dart';
import 'toolkit_controller.dart';
import 'turn.dart';

/// A request a running answer waits on, as the app shows it: the [answer] that named it, in
/// workspace [slug], and the request as the bridge holds it, or the [problem] that kept it from
/// being read.
class AskShown {
  AskShown(this.id, this.slug, this.answer);

  final String id;
  final String slug;
  final Turn answer;

  /// The request, or null when it could not be read.
  Ask? ask;

  /// Why it could not be read or answered, or that it can no longer be.
  Notice? problem;

  /// Whether it can no longer be answered: answered elsewhere, or the skill stopped waiting.
  bool ended = false;
}

/// The requests the toolkit's skills wait on while an answer runs, which the app asks the
/// person about one at a time ([current]), and the hosts the person always allows. It follows
/// each running answer's status line for a request ([Turn.ask]), reads it from the bridge, and
/// shows it only when it belongs to that answer's workspace: what shows is what the bridge
/// holds, never the status line. A request goes when it is answered, when the answer goes on
/// without it or ends, and on another server. Out of sight, the request on screen shows as a
/// notification through [BackgroundWork.asking].
class AskController extends ChangeNotifier {
  AskController(
    this._api,
    this._toolkit,
    this._chat, {
    BackgroundWork? background,
  }) : _background = background,
       _epoch = _toolkit.epoch {
    _chat.addListener(_followRuns);
    _toolkit.addListener(_toolkitChanged);
    if (background != null) {
      _life = AppLifecycleListener(
        onStateChange: (state) {
          _front = state == AppLifecycleState.resumed;
          _note();
        },
      );
    }
    _followRuns();
  }

  final ToolkitApi _api;
  final ToolkitController _toolkit;
  final ChatController _chat;
  final BackgroundWork? _background;
  AppLifecycleListener? _life;

  /// Whether the app is on screen. Before Android says, it is, as at start.
  bool _front = true;

  /// The toolkit's [ToolkitController.epoch] what is held was read under.
  int _epoch;

  /// Whether the toolkit lets skills ask here.
  bool get served => _toolkit.serves(ToolkitFeature.asks);

  /// The requests to ask about, the first on screen.
  final _shown = <AskShown>[];

  /// The request on screen, or null.
  AskShown? get current => _shown.firstOrNull;

  /// Whether an answer to [current] is on its way.
  bool busy = false;

  /// The requests read on this server, so each is asked about once.
  final _seen = <String>{};

  /// What listens to each running answer.
  final _listened = <Turn, VoidCallback>{};

  /// Ends [current] when its skill stops waiting.
  Timer? _expiry;

  /// The request the notification shows, or null while none does.
  AskShown? _noted;

  /// The hosts skills may always reach, or null until read.
  List<AllowedHost>? allowed;

  /// Why the last read or change of [allowed] failed.
  Notice? allowedProblem;
  bool allowedLoading = false;

  /// Whether a host is being removed.
  bool allowedBusy = false;
  bool _allowedAsked = false;

  void _followRuns() {
    final running = {for (final r in _chat.running) r.answer: r.slug};
    for (final turn in [..._listened.keys]) {
      if (running.containsKey(turn)) continue;
      turn.removeListener(_listened.remove(turn)!);
      _drop(turn);
    }
    for (final MapEntry(key: turn, value: slug) in running.entries) {
      if (_listened.containsKey(turn)) continue;
      void heard() => _heard(turn, slug);
      _listened[turn] = heard;
      turn.addListener(heard);
      heard();
    }
  }

  void _heard(Turn turn, String slug) {
    final id = turn.ask;
    // The skill went on: the request was answered elsewhere or it stopped waiting.
    if (_shown.any((s) => s.answer == turn && s.id != id)) _drop(turn);
    if (id == null || !served || !_seen.add(id)) return;
    unawaited(_read(id, slug, turn));
  }

  Future<void> _read(String id, String slug, Turn turn) async {
    final asked = _epoch;
    final shown = AskShown(id, slug, turn);
    try {
      shown.ask = await _api.ask(id);
    } on ApiException catch (error) {
      // A request that is gone no longer waits.
      if (error.status == 404) return;
      shown.problem = Notice('Could not read the request', error.message);
    }
    if (asked != _epoch || turn.ask != id || !_listened.containsKey(turn)) {
      return;
    }
    if (shown.ask case final ask?
        when ask.workspace != slug ||
            ask.decision != null ||
            ask.expiredAt(clock.now())) {
      return;
    }
    _shown.add(shown);
    _changed();
  }

  /// Answers [current] with [decision].
  Future<void> decide(AskDecision decision) async {
    final shown = current;
    final ask = shown?.ask;
    if (shown == null || ask == null || shown.ended || busy) return;
    final asked = _epoch;
    busy = true;
    shown.problem = null;
    notifyListeners();
    try {
      await _api.decide(ask.id, decision);
      if (asked != _epoch) return;
      _shown.remove(shown);
      // The list of hosts always allowed has one more.
      if (decision == AskDecision.always) _allowedAsked = false;
    } on ApiException catch (error) {
      if (asked != _epoch) return;
      if (error.status == 409) {
        shown.ended = true;
        shown.problem = Notice('It no longer waits', error.message);
      } else {
        shown.problem = Notice('Could not answer it', error.message);
      }
    } finally {
      busy = false;
      if (asked == _epoch) _changed();
    }
  }

  /// Closes [current]: a request that still waits is refused, as Deny does.
  void dismiss() {
    final shown = current;
    if (shown == null || busy) return;
    if (shown.ask != null && !shown.ended) {
      unawaited(decide(AskDecision.deny));
      return;
    }
    _shown.remove(shown);
    _changed();
  }

  /// Forgets the requests [answer] named.
  void _drop(Turn answer) {
    final before = _shown.length;
    _shown.removeWhere((s) => s.answer == answer);
    if (_shown.length != before) _changed();
  }

  /// Times [current]'s end, says out of sight that it waits, and tells the listeners.
  void _changed() {
    _expiry?.cancel();
    _expiry = null;
    final shown = current;
    if (shown?.ask case final ask? when !shown!.ended) {
      _expiry = Timer(ask.expires.difference(clock.now()), () {
        if (!identical(current, shown)) return;
        shown
          ..ended = true
          ..problem = const Notice(
            'The time ran out',
            'The skill went on without it, as if you had said no.',
          );
        _changed();
      });
    }
    _note();
    notifyListeners();
  }

  /// Shows the request on screen as a notification while the app is out of sight, or takes it
  /// back.
  void _note() {
    final background = _background;
    if (background == null) return;
    final shown = current;
    final want = !_front && shown?.ask != null && !shown!.ended ? shown : null;
    if (identical(want, _noted)) return;
    _noted = want;
    final ask = want?.ask;
    final thread = _chat.running
        .where((r) => r.answer == want?.answer)
        .firstOrNull
        ?.thread;
    if (want == null || ask == null || thread == null) {
      unawaited(background.asked());
      return;
    }
    final workspace = _chat.workspaces
        .where((w) => w.slug == want.slug)
        .firstOrNull
        ?.name;
    unawaited(
      background.asking(
        title: 'Approval needed in ${workspace ?? 'AnythingLLM'}',
        body: '${ask.skill} asks to reach ${ask.host}.',
        slug: want.slug,
        thread: thread,
      ),
    );
  }

  void _toolkitChanged() {
    if (_toolkit.epoch == _epoch && (served || _shown.isEmpty)) return;
    if (_toolkit.epoch != _epoch) {
      _epoch = _toolkit.epoch;
      _seen.clear();
      allowed = null;
      allowedProblem = null;
      allowedLoading = false;
      allowedBusy = false;
      _allowedAsked = false;
    }
    _shown.clear();
    busy = false;
    _changed();
  }

  /// Reads the hosts always allowed, when the toolkit serves them and they are not read yet.
  /// It notifies only when the read ends, so a page may ask while it builds.
  void wantAllowed() {
    if (!served || _allowedAsked) return;
    _allowedAsked = true;
    allowedLoading = true;
    unawaited(_readAllowed());
  }

  Future<void> _readAllowed() async {
    final asked = _epoch;
    try {
      final hosts = await _api.allowedHosts();
      if (asked != _epoch) return;
      allowed = hosts;
      allowedProblem = null;
    } on ApiException catch (error) {
      if (asked != _epoch) return;
      allowedProblem = Notice(
        'Could not read the allowed hosts',
        error.message,
      );
    }
    allowedLoading = false;
    notifyListeners();
  }

  /// Stops always allowing [host]. Whether it went.
  Future<bool> forget(String host) async {
    if (allowedBusy) return false;
    final asked = _epoch;
    allowedBusy = true;
    allowedProblem = null;
    notifyListeners();
    try {
      final hosts = await _api.forgetHost(host);
      if (asked != _epoch) return false;
      allowed = hosts;
      return true;
    } on ApiException catch (error) {
      if (asked != _epoch) return false;
      allowedProblem = Notice('Could not remove $host', error.message);
      return false;
    } finally {
      if (asked == _epoch) {
        allowedBusy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _chat.removeListener(_followRuns);
    _toolkit.removeListener(_toolkitChanged);
    for (final MapEntry(key: turn, value: heard) in _listened.entries) {
      turn.removeListener(heard);
    }
    _expiry?.cancel();
    _life?.dispose();
    if (_noted != null) unawaited(_background?.asked());
    super.dispose();
  }
}
