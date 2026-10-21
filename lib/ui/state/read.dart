import 'package:flutter/scheduler.dart';

import '../../core/errors.dart';
import 'notice.dart';

/// Runs [read] once the frame being built is done: a read tells the controller's listeners at
/// once, and a widget asks for one as it builds.
void afterFrame(VoidCallback read) =>
    SchedulerBinding.instance.addPostFrameCallback((_) => read());

/// One thing a controller reads from the server: what the last read found ([value]), why it
/// failed ([problem]), and the read on its way ([pending]). Only the newest read's answer is
/// kept: a read begun after it, [take] or [reset] drops it.
class ReadSlot<T> {
  /// Tells the controller's listeners through [_notify].
  ReadSlot(this._notify);

  final VoidCallback _notify;

  T? value;
  Notice? problem;
  Future<void>? pending;

  /// Counts the reads begun and dropped, so an answer is kept only when no read began after it.
  int _go = 0;

  /// Whether a read is on its way.
  bool get loading => pending != null;

  /// Whether it was read, refused, or is being read.
  bool get asked => value != null || problem != null || pending != null;

  /// Forgets what was read, and frees the slot for the next read. The read on its way is dropped
  /// too, unless [dropRead] is false: then it is kept if it is still the newest, and its
  /// `current` holds, when it is answered.
  void reset({bool dropRead = true}) {
    value = null;
    problem = null;
    pending = null;
    if (dropRead) _go++;
  }

  /// Keeps [value] over what the read on its way would bring, as a save that wrote it does, and
  /// frees the slot for the next read.
  void take(T value) {
    _go++;
    pending = null;
    this.value = value;
  }

  /// Reads with [fetch] into [value], or into [problem], titled [failTitle], when the server
  /// refuses; [failed], when given, takes that notice in place of [problem], and [kept] runs once
  /// an answer is kept. An answer is kept only while it is the newest read and [current] holds.
  /// With [join], a read on its way is waited for instead, then read afresh only [again]. It
  /// tells the listeners as it starts, unless [quiet], and once it is kept or refused. A failure
  /// other than an [ApiException] frees the slot and is thrown on.
  Future<void> read(
    Future<T> Function() fetch, {
    required String failTitle,
    bool Function()? current,
    void Function(T read)? kept,
    void Function(Notice why)? failed,
    bool join = false,
    bool again = false,
    bool quiet = false,
  }) async {
    if (pending case final on? when join) {
      await on;
      if (!again) return;
    }
    final go = ++_go;
    bool newest() => go == _go && (current?.call() ?? true);
    final reading = pending = () async {
      try {
        final read = await fetch();
        if (!newest()) return;
        value = read;
        problem = null;
        kept?.call(read);
      } on ApiException catch (error) {
        if (!newest()) return;
        final why = Notice(failTitle, error.message);
        if (failed != null) {
          failed(why);
        } else {
          problem = why;
        }
      } finally {
        // A newer read, or a reset, has the slot by then.
        if (newest()) {
          pending = null;
          _notify();
        }
      }
    }();
    if (!quiet) _notify();
    await reading;
  }
}

/// Sends [call], then, while [current] holds, has [readAgain] read what it changed, whether it
/// went or not, and show why it failed over what it read: a notice titled [failTitle], or null
/// when it went. [busy], when given, is told as the call starts and, while [current] holds, once
/// it ends, however it ended. Whether it went; a failure other than an [ApiException] is thrown
/// on.
Future<bool> changeThenRead(
  String failTitle,
  Future<void> Function() call, {
  required bool Function() current,
  required Future<void> Function(Notice? failed) readAgain,
  void Function(bool busy)? busy,
}) async {
  busy?.call(true);
  Notice? failed;
  try {
    await call();
  } on ApiException catch (error) {
    failed = Notice(failTitle, error.message);
  } finally {
    // A failure of any kind leaves the controller free for the next change.
    if (current()) busy?.call(false);
  }
  if (!current()) return false;
  await readAgain(failed);
  return failed == null;
}
