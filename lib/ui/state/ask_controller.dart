import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../../core/asks.dart';
import '../../core/ports.dart';
import '../chat/background_work.dart';
import 'chat_controller.dart';
import 'notice.dart';
import 'toolkit_controller.dart';

/// A request a running answer waits on, as the app shows it: the answer in chat [thread] of
/// workspace [slug] that named it, and the request as the bridge holds it, or the [problem]
/// that kept it from being read.
class AskShown {
  AskShown(this.id, this.slug, this.thread);

  final String id;
  final String slug;
  final String thread;

  /// The request, or null when it could not be read.
  Ask? ask;

  /// Why it could not be read or answered, or that it can no longer be.
  Notice? problem;

  /// Whether it can no longer be answered: answered elsewhere, or the skill stopped waiting.
  bool ended = false;
}

/// The requests the toolkit's skills wait on while an answer runs, which the app asks the
/// person about one at a time ([current]). It follows the requests the running answers' status
/// lines name ([ChatController.asks]), reads each from the bridge, and shows it only when it
/// belongs to that answer's workspace: what shows is what the bridge holds, never the status
/// line. A request goes when it is answered, when the answer goes on without it or ends, and on
/// another server. Out of sight ([KeepAnswering.front]), the request on screen shows as a
/// notification through [BackgroundWork.asking].
class AskController extends ChangeNotifier {
  AskController(this._api, this._toolkit, this._chat, {KeepAnswering? keep})
    : _keep = keep,
      _epoch = _toolkit.epoch {
    _heard = _chat.asks.listen(_onHeard);
    _toolkit.addListener(_toolkitChanged);
    keep?.front.addListener(_note);
  }

  final ToolkitApi _api;
  final ToolkitController _toolkit;
  final ChatController _chat;
  final KeepAnswering? _keep;
  late final StreamSubscription<AskHeard> _heard;

  /// The toolkit's [ToolkitController.epoch] what is held was read under.
  int _epoch;

  /// The requests to ask about, the first on screen.
  final _shown = <AskShown>[];

  final _current = ValueNotifier<AskShown?>(null);

  /// The request on screen, or null.
  ValueListenable<AskShown?> get current => _current;

  /// Whether an answer to [current] is on its way.
  bool busy = false;

  /// The requests read on this server, so each is asked about once.
  final _seen = <String>{};

  /// The request each running answer's latest status line names, by chat.
  final _waiting = <String, String>{};

  /// Ends [current] when its skill stops waiting.
  Timer? _expiry;

  /// The request the notification shows, or null while none does.
  AskShown? _noted;

  void _onHeard(AskHeard heard) {
    final (:slug, :thread, :id) = heard;
    if (id == null) {
      _waiting.remove(thread);
    } else {
      _waiting[thread] = id;
    }
    // The skill went on: the request was answered elsewhere or it stopped waiting.
    final before = _shown.length;
    _shown.removeWhere((s) => s.thread == thread && s.id != id);
    if (_shown.length != before) _changed();
    if (id == null || !_toolkit.asksServed || !_seen.add(id)) return;
    unawaited(_read(id, slug, thread));
  }

  Future<void> _read(String id, String slug, String thread) async {
    final asked = _epoch;
    final shown = AskShown(id, slug, thread);
    try {
      shown.ask = await _api.ask(id);
    } on ApiException catch (error) {
      // A request that is gone no longer waits.
      if (error.status == 404) return;
      shown.problem = Notice('Could not read the request', error.message);
    }
    if (asked != _epoch || _waiting[thread] != id) return;
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
    final shown = _current.value;
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
      // The list of addresses always allowed has one more.
      if (decision == AskDecision.always) {
        unawaited(_toolkit.readAllowed(again: true));
      }
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
    final shown = _current.value;
    if (shown == null || busy) return;
    if (shown.ask != null && !shown.ended) {
      unawaited(decide(AskDecision.deny));
      return;
    }
    _shown.remove(shown);
    _changed();
  }

  /// Puts the first request on screen, times its end, says out of sight that it waits, and
  /// tells the listeners.
  void _changed() {
    _expiry?.cancel();
    _expiry = null;
    final shown = _current.value = _shown.firstOrNull;
    if (shown?.ask case final ask? when !shown!.ended) {
      _expiry = Timer(ask.expires.difference(clock.now()), () {
        if (!identical(_current.value, shown)) return;
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
    final keep = _keep;
    if (keep == null) return;
    final shown = _current.value;
    final want = !keep.front.value && shown?.ask != null && !shown!.ended
        ? shown
        : null;
    if (identical(want, _noted)) return;
    _noted = want;
    final ask = want?.ask;
    if (want == null || ask == null) {
      unawaited(keep.work.asked());
      return;
    }
    final workspace = _chat.workspaceOf(want.slug)?.name;
    unawaited(
      keep.work.asking(
        title: 'Approval needed in ${workspace ?? 'AnythingLLM'}',
        body: '${ask.skill} asks to reach ${ask.origin}.',
        slug: want.slug,
        thread: want.thread,
      ),
    );
  }

  void _toolkitChanged() {
    final served = _toolkit.asksServed;
    if (_toolkit.epoch == _epoch && (served || _shown.isEmpty)) return;
    if (_toolkit.epoch != _epoch) {
      _epoch = _toolkit.epoch;
      _seen.clear();
    }
    _shown.clear();
    busy = false;
    _changed();
  }

  @override
  void dispose() {
    unawaited(_heard.cancel());
    _toolkit.removeListener(_toolkitChanged);
    _keep?.front.removeListener(_note);
    _expiry?.cancel();
    if (_noted != null) unawaited(_keep?.work.asked());
    _current.dispose();
    super.dispose();
  }
}
