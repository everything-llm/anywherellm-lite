import 'dart:async';
import 'dart:math';

import '../../core/ports.dart';
import '../../core/server_models.dart';
import 'turn.dart';

/// An answer whose connection dropped, read for in its chat's history until the server saved
/// it, or [AnswerWaits.waitReads] reads found nothing.
class _Waiting {
  _Waiting(this.answer, this.slug, this.thread, this.question);

  final Turn answer;
  final String slug;
  final String thread;

  /// The question [answer] answers, trimmed.
  final String question;

  /// The newest exchange the server had saved before the answer: as the chat knew it when the
  /// answer dropped, or else as the first read that did not find the answer saw it; null until
  /// then.
  int? floor;

  /// How many times the chat was read for it so far.
  int reads = 0;
  Timer? next;

  /// The read under way, which another check joins.
  Future<void>? reading;

  void cancel() => next?.cancel();
}

/// The answers whose connection dropped while AnythingLLM may still finish them, by chat, each
/// read for in its chat's history until the server saved it.
class AnswerWaits {
  AnswerWaits(
    this._api, {
    required this.turnsOf,
    required this.saved,
    required this.changed,
  });

  final AnythingLlmApi _api;

  /// The turns chat `thread` shows, or null when it shows none.
  final List<Turn>? Function(String thread) turnsOf;

  /// Takes what the server saved for chat `thread`, whose last turn is the answer waited for.
  final void Function(String slug, String thread, List<Turn> saved) saved;

  /// Says that the wait in chat `thread` ended.
  final void Function(String thread) changed;

  /// How many times the chat of an answer whose connection dropped is read before it counts as
  /// failed: every 5 s for 2 minutes, then every 20 s to 30 minutes.
  static const waitReads = 24 + 84;
  static const _quickReads = 24;

  static const _movedOn =
      'The connection dropped before this answer came. Pull down to read what the server '
      'saved.';

  final _waits = <String, _Waiting>{};

  /// Whether any answer is waited for.
  bool get any => _waits.isNotEmpty;

  /// The workspace of an answer waited for, or null.
  String? get firstSlug => _waits.values.firstOrNull?.slug;

  /// Whether chat [thread]'s answer is waited for.
  bool has(String thread) => _waits.containsKey(thread);

  /// Waits for [answer], the last turn of chat [thread] in workspace [slug], whose exchange is
  /// newer than [after], the newest the server had saved before it, when that is known.
  void start(Turn answer, String slug, String thread, {int? after}) {
    final turns = turnsOf(thread) ?? const [];
    final at = turns.indexOf(answer);
    final question = at > 0 ? turns[at - 1].text.trim() : '';
    final waiting = _Waiting(answer, slug, thread, question)..floor = after;
    // An answer already waited for in this chat is let go of, as when the chat moves on.
    if (_waits[thread] case final old?) {
      old.cancel();
      if (!identical(old.answer, answer)) {
        old.answer.error = _movedOn;
        old.answer.stopWaiting();
      }
    }
    _waits[thread] = waiting;
    answer.waiting = true;
    _checkLater(waiting);
  }

  /// Reads chat [thread] now for its answer, or joins the read under way.
  Future<void> check(String thread) =>
      _waits[thread] == null ? Future.value() : _check(_waits[thread]!);

  /// Reads each chat whose answer is waited for now, as when the app comes back to the front
  /// or Check now is tapped.
  Future<void> checkAll() => Future.wait([
    for (final waiting in [..._waits.values]) _check(waiting),
  ]);

  /// Stops every wait, as a new server does.
  void clear() {
    for (final waiting in _waits.values) {
      waiting.cancel();
    }
    _waits.clear();
  }

  /// Reads the chat again for [waiting]'s answer: every 5 s at first, then every 20 s.
  void _checkLater(_Waiting waiting) {
    waiting.cancel();
    waiting.next = Timer(
      Duration(seconds: waiting.reads < _quickReads ? 5 : 20),
      () => unawaited(_check(waiting)),
    );
  }

  Future<void> _check(_Waiting waiting) {
    waiting.cancel();
    return waiting.reading ??= _read(waiting)
        .whenComplete(() => waiting.reading = null);
  }

  /// Takes [waiting]'s answer from its chat's history once the server saved it ([_holds]).
  /// After [waitReads] reads the answer fails; a chat that moved on, as by a new message, stops
  /// the reading and says why the answer is missing. A wait [clear] ended changes nothing.
  Future<void> _read(_Waiting waiting) async {
    final (answer, slug, thread) = (
      waiting.answer,
      waiting.slug,
      waiting.thread,
    );
    waiting.reads++;
    List<ChatMessage>? history;
    try {
      history = await _api.history(slug, thread);
    } on Object {
      // Out of reach for now, or a read that failed some other way: read again next time.
    }
    if (!identical(_waits[thread], waiting)) return;
    final turns = turnsOf(thread);
    if (turns == null || !identical(turns.lastOrNull, answer)) {
      answer.error = _movedOn;
      return _end(waiting);
    }
    if (history != null) {
      if (_holds(waiting, turns, history)) {
        saved(slug, thread, [for (final m in history) Turn.saved(m)]);
        return _end(waiting);
      }
      waiting.floor = history.map((m) => m.chatId ?? -1).fold<int>(-1, max);
    }
    if (waiting.reads >= waitReads) {
      answer.error = 'The connection dropped, and the server saved no answer within 30 minutes.';
      return _end(waiting);
    }
    _checkLater(waiting);
  }

  /// Ends [waiting], with whatever was set on its answer, telling both once.
  void _end(_Waiting waiting) {
    waiting.cancel();
    _waits.remove(waiting.thread);
    waiting.answer.stopWaiting();
    changed(waiting.thread);
  }

  /// Whether [history] ends in [waiting]'s answer: its last exchange is newer than the
  /// [_Waiting.floor]. With none known, the exchange must be newer than every one [turns] know,
  /// ask [_Waiting.question], and the history must ask it as often as [turns] do: an agent
  /// answer streamed here has no id, so its exchange can look new.
  static bool _holds(
    _Waiting waiting,
    List<Turn> turns,
    List<ChatMessage> history,
  ) {
    if (history case [
      ...,
      final asked,
      ChatMessage(role: Role.assistant, chatId: final int id),
    ]) {
      if (waiting.floor case final floor?) return id > floor;
      bool asks(Role role, String text) =>
          role == Role.user && text.trim() == waiting.question;
      return turns.every((t) => t.chatId == null || t.chatId! < id) &&
          asks(asked.role, asked.text) &&
          history.where((m) => asks(m.role, m.text)).length >=
              turns.where((t) => !t.notSent && asks(t.role, t.text)).length;
    }
    return false;
  }
}
