import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ports.dart';
import '../../core/sources.dart';
import '../../core/upload.dart';
import 'chat_controller.dart';
import 'notice.dart';
import 'prefs_controller.dart';

/// The active workspace's Sources: what it answers from, adding files, switching them on and off,
/// and removing them with a short chance to undo.
///
/// Switching a file off takes it out of the workspace on the server and remembers it here, so it
/// stays listed. Removing forgets it altogether; the file stays in the server's documents.
class SourcesController extends ChangeNotifier {
  SourcesController(this._api, this._chat, this._prefs) {
    _chat.addListener(_chatChanged);
  }

  final AnythingLlmApi _api;
  final ChatController _chat;
  final PrefsController _prefs;

  /// The workspace [files] describe.
  String? _slug;

  List<SourceFile> files = const [];
  bool loading = false;

  /// The extensions the server reads, or null when it has not said. Then the server decides.
  Set<String>? _accepted;

  /// The file being sent now, or null.
  String? sending;

  /// Why the last load or change failed, one notice per file that could not be added.
  List<Notice> problems = const [];

  /// The file just removed, for the undo toast.
  SourceFile? removed;
  Timer? _removedTimer;

  /// The file a citation pointed at, lit up for a moment.
  String? flashed;
  Timer? _flashTimer;

  static const undoFor = Duration(seconds: 6);
  static const flashFor = Duration(milliseconds: 1800);

  int get onCount => files.where((f) => f.on).length;

  /// The file titled [title], or null when it is no longer in Sources.
  SourceFile? byTitle(String title) =>
      files.where((f) => f.title == title).firstOrNull;

  @override
  void dispose() {
    _chat.removeListener(_chatChanged);
    _removedTimer?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }

  void _chatChanged() {
    if (_chat.activeSlug == _slug) return;
    _slug = _chat.activeSlug;
    files = const [];
    problems = const [];
    _clearRemoved();
    notifyListeners();
    if (_slug != null) unawaited(refresh());
  }

  /// Reads the active workspace's documents again.
  Future<void> refresh() async {
    final slug = _slug;
    if (slug == null) return;
    loading = true;
    notifyListeners();
    try {
      final workspace = await _api.workspace(slug);
      if (slug != _slug) return;
      files = mergeSources(workspace.documents, _prefs.prefs.offIn(slug));
      _chat.setDocCount(slug, workspace.documents.length);
    } on ApiException catch (error) {
      if (slug != _slug) return;
      problems = [
        Notice('Could not read this workspace\'s files', error.message),
      ];
    } finally {
      if (slug == _slug) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// Switches [file] on, embedding it in the workspace, or off, taking it out.
  Future<void> toggle(SourceFile file) => _change(
    file.on
        ? 'Could not switch ${file.title} off'
        : 'Could not switch ${file.title} on',
    (slug) async {
      await _embed(slug, file, on: !file.on);
      await _remember(slug, file, off: file.on);
    },
  );

  /// Sends each file in turn, then embeds all the server made of them at once. Each file that
  /// cannot be added says why, and the rest still go.
  Future<void> upload(List<UploadFile> picked) async {
    final slug = _slug;
    if (slug == null || picked.isEmpty) return;
    final refused = <Notice>[];
    final made = <String>[];
    try {
      _accepted ??= await _api.acceptedExtensions();
    } on ApiException {
      // The server decides each file then.
    }
    for (final file in picked) {
      sending = file.name;
      notifyListeners();
      try {
        final wrongType = extensionProblem(file.name, _accepted);
        if (wrongType != null) throw ApiException(wrongType);
        final docs = await _api.upload(file.name, await file.read());
        made.addAll([for (final d in docs) d.path]);
      } on Exception catch (error) {
        if (error is! ApiException && error is! UnreadableFile) rethrow;
        refused.add(Notice('Could not add ${file.name}', '$error'));
      }
    }
    if (made.isNotEmpty) {
      try {
        await _api.updateEmbeddings(slug, adds: made);
      } on ApiException catch (error) {
        refused.add(
          Notice('Could not add the files to this workspace', error.message),
        );
      }
    }
    sending = null;
    problems = refused;
    await refresh();
  }

  /// Takes [file] out of Sources. [undo] puts it back for a few seconds after.
  Future<void> remove(SourceFile file) =>
      _change('Could not remove ${file.title}', (slug) async {
        if (file.on) {
          await _embed(slug, file, on: false);
        } else {
          await _remember(slug, file, off: false);
        }
        _clearRemoved();
        removed = file;
        _removedTimer = Timer(undoFor, () {
          removed = null;
          notifyListeners();
        });
      });

  Future<void> undo() async {
    final file = removed;
    if (file == null) return;
    _clearRemoved();
    await _change('Could not put ${file.title} back', (slug) async {
      if (file.on) {
        await _embed(slug, file, on: true);
      } else {
        await _remember(slug, file, off: true);
      }
    });
  }

  /// Lights up the file titled [title] for a moment.
  void flash(String title) {
    final file = byTitle(title);
    if (file == null) return;
    _flashTimer?.cancel();
    flashed = file.path;
    _flashTimer = Timer(flashFor, () {
      flashed = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Shows a failure that is not about one file, such as a file picker that would not open.
  void report(String title, String text) {
    problems = [...problems, Notice(title, text)];
    notifyListeners();
  }

  void _clearRemoved() {
    _removedTimer?.cancel();
    removed = null;
  }

  /// Puts [file] in the workspace on the server, or takes it out.
  Future<void> _embed(String slug, SourceFile file, {required bool on}) =>
      _api.updateEmbeddings(
        slug,
        adds: [if (on) file.path],
        deletes: [if (!on) file.path],
      );

  /// Adds [file] to the workspace's remembered switched-off files, or drops it from them.
  Future<void> _remember(String slug, SourceFile file, {required bool off}) =>
      _prefs.setOff(slug, [
        for (final doc in _prefs.prefs.offIn(slug))
          if (doc.path != file.path) doc,
        if (off) file.asOff,
      ]);

  Future<void> _change(
    String failTitle,
    Future<void> Function(String) op,
  ) async {
    final slug = _slug;
    if (slug == null) return;
    try {
      await op(slug);
      problems = const [];
    } on ApiException catch (error) {
      problems = [Notice(failTitle, error.message)];
    }
    await refresh();
  }
}
