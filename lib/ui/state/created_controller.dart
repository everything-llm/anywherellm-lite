import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../core/connection.dart';
import '../../core/created.dart';
import '../../core/ports.dart';
import 'chat_controller.dart';
import 'notice.dart';
import 'settings_controller.dart';

/// The files the agent's code left in the open workspace's sandbox and its apps, as the
/// everythingllm host lists them, and what the person does with each: Download, Keep and
/// Delete. A workspace or a
/// server that shows afresh starts it afresh. A server without the host's route leaves
/// [unavailable] set, and is not asked again until another server shows.
class CreatedController extends ChangeNotifier {
  CreatedController(this._api, this._settings, this._chat) {
    _settings.addListener(_changed);
    _chat.addListener(_changed);
    _of = _here;
  }

  final AnythingLlmApi _api;
  final SettingsController _settings;
  final ChatController _chat;

  /// The server and workspace [list] describes.
  ({Connection? server, String? slug})? _of;

  /// The files, or null before they are read.
  CreatedList? list;

  /// Whether the server has no route to list them by.
  bool unavailable = false;

  /// Whether the files are being read.
  bool loading = false;

  /// Why the last read or change failed.
  Notice? problem;

  /// The ids of the files and apps being kept or deleted.
  final Set<String> working = {};

  int _reads = 0;

  ({Connection? server, String? slug}) get _here => (
    server: _settings.connection?.withPassword(null),
    slug: _chat.activeSlug,
  );

  void _changed() {
    final here = _here;
    if (here == _of) return;
    _of = here;
    _reads++;
    list = null;
    unavailable = false;
    loading = false;
    problem = null;
    working.clear();
    notifyListeners();
  }

  /// Reads the files unless they are read already, or the server cannot say, or the last read
  /// failed (Refresh asks again). It asks after the frame, since a read tells the listeners at
  /// once, so a build may call it.
  void want() {
    if (list != null || unavailable || loading || problem != null) return;
    if (_of?.slug == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (list == null && !loading) unawaited(read());
    });
  }

  /// Reads the open workspace's files again.
  Future<void> read() async {
    final here = _of;
    final slug = here?.slug;
    if (slug == null || here?.server == null) return;
    final number = ++_reads;
    loading = true;
    notifyListeners();
    try {
      final read = await _api.createdFiles(slug);
      if (number != _reads) return;
      unavailable = read == null;
      list = read;
      problem = null;
    } on ApiException catch (error) {
      if (number != _reads) return;
      problem = Notice('Could not read the created files', error.message);
    }
    loading = false;
    notifyListeners();
  }

  /// Shows [title] and [text] as the [problem], as when a file could not be saved.
  void report(String title, String text) {
    problem = Notice(title, text);
    notifyListeners();
  }

  /// The bytes of [file], or null when they could not be read, and why shows as [problem].
  Future<List<int>?> bytes(CreatedFile file) async {
    final here = _of;
    final slug = here?.slug;
    if (slug == null) return null;
    try {
      return await _api.downloadCreated(slug, file.id);
    } on ApiException catch (error) {
      if (_of == here) {
        problem = Notice('Could not get ${file.name}', error.message);
        notifyListeners();
      }
      return null;
    }
  }

  /// Moves the working [file] into the workspace's project folder, where it stays.
  Future<void> keep(CreatedFile file) =>
      _change(file, 'keep', (slug) => _api.keepCreated(slug, file.id));

  /// Deletes [item], a file or an app, from the workspace.
  Future<void> remove(Created item) =>
      _change(item, 'delete', (slug) => _api.deleteCreated(slug, item.id));

  Future<void> _change(
    Created item,
    String verb,
    Future<void> Function(String slug) call,
  ) async {
    final here = _of;
    final slug = here?.slug;
    if (slug == null || !working.add(item.id)) return;
    problem = null;
    notifyListeners();
    Notice? failed;
    try {
      await call(slug);
    } on ApiException catch (error) {
      failed = Notice('Could not $verb ${item.label}', error.message);
    }
    if (_of != here) return;
    working.remove(item.id);
    notifyListeners();
    // What the host has now, whether the change went or not.
    await read();
    if (failed != null && _of == here) {
      problem = failed;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_changed);
    _chat.removeListener(_changed);
    super.dispose();
  }
}
