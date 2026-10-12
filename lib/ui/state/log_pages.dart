import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/apps.dart';
import '../../core/ports.dart';

/// An app's log as far as it is read, newest line first: the newest page, then each older
/// page on [older]. An apps server without the paged route gives the whole `log.jsonl` at
/// once, and [paged] is then false.
class LogPages extends ChangeNotifier {
  LogPages(this._api, this.app);

  final AppsApi _api;
  final AppRef app;

  /// The lines read so far, newest first.
  List<LogLine> lines = const [];

  /// The first line the log holds, from which the app can be put back; null until a page
  /// says, or from an apps server that does not.
  int? first;

  /// Whether lines older than those read remain.
  bool more = false;

  /// Whether the log is read a page at a time; false once the whole file was read instead.
  bool paged = true;

  /// Whether the first read has ended, however it ended.
  bool loaded = false;

  /// Whether a page is being read.
  bool reading = false;

  /// Why the last read failed, or null.
  String? problem;

  /// Set once the controller lets go of it, after which a read's answer changes nothing.
  bool _gone = false;

  /// Reads the newest page, as the log first shows.
  Future<void> start() => _read(null);

  /// Reads the page before the oldest line read, unless none remains or one is being read.
  Future<void> older() async {
    if (!more || reading || lines.isEmpty) return;
    await _read(lines.last.n);
  }

  Future<void> _read(int? before) async {
    reading = true;
    problem = null;
    _tell();
    try {
      final page = await _api.log(app, before: before);
      if (_gone) return;
      if (page == null) {
        // An older apps server: the whole file at once.
        lines = logLinesOf(await _api.file(app, 'log.jsonl'));
        if (_gone) return;
        paged = false;
        more = false;
      } else {
        lines = [
          ...?(before == null ? null : lines),
          for (final line in page.lines)
            if (before == null || line.n < before) line,
        ];
        first = page.first;
        more = page.more && page.lines.isNotEmpty;
      }
    } on ApiException catch (error) {
      if (_gone) return;
      problem = error.message;
    } finally {
      if (!_gone) {
        loaded = true;
        reading = false;
        _tell();
      }
    }
  }

  void _tell() {
    if (!_gone) notifyListeners();
  }

  /// Lets go of it: a read still going changes nothing.
  void leave() => _gone = true;
}
