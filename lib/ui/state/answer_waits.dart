import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ports.dart';
import '../../core/server_models.dart';
import 'turn.dart';

/// An answer whose connection dropped, read for in its chat's history until the server saved
/// it, or [AnswerWaits.waitReads] reads found nothing.
class _Waiting {
  _Waiting(this.answer, this.slug, this.thread);

  final Turn answer;
  final String slug;
  final String thread;

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

  /// Says that a wait ended.
  final VoidCallback changed;

  /// How many times the chat of an answer whose connection dropped is read before it counts as
  /// failed: every 5 s for 2 minutes, then every 20 s to 30 minutes.
  static const waitReads = 24 + 84;
  static const _quickReads = 24;

  final _waits = <String, _Waiting>{};

  /// Whether any answer is waited for.
  bool get any => _waits.isNotEmpty;

  /// The workspace of an answer waited for, or null.
  String? get firstSlug => _waits.values.firstOrNull?.slug;

  /// Whether chat [thread]'s answer is waited for.
  bool has(String thread) => _waits.containsKey(thread);

  /// Waits for [answer], the last turn of chat [thread] in workspace [slug].
  void start(Turn answer, String slug, String thread) {
    final waiting = _Waiting(answer, slug, thread);
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

  /// Takes [waiting]'s answer from its chat's history once the server saved it: a last exchange
  /// newer than every one the chat showed. After [waitReads] reads the answer fails; a chat that
  /// moved on, as by a new message, stops the reading. A wait [clear] ended changes nothing.
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
    } on ApiException {
      // Out of reach for now: read again next time.
    }
    if (!identical(_waits[thread], waiting)) return;
    final turns = turnsOf(thread);
    if (turns == null || !identical(turns.lastOrNull, answer)) {
      return _end(waiting);
    }
    if (history case [..., final said]
        when said.role == Role.assistant &&
            said.chatId != null &&
            _newerThanAll(turns, said.chatId!)) {
      saved(slug, thread, [for (final m in history) Turn.saved(m)]);
      return _end(waiting);
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
    changed();
  }

  /// Whether [id] is newer than every exchange [turns] know, so it was saved after them.
  static bool _newerThanAll(List<Turn> turns, int id) =>
      turns.every((t) => t.chatId == null || t.chatId! < id);
}
