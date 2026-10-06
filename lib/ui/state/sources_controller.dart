import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/chat.dart';
import '../../core/ports.dart';
import '../../core/server_models.dart';
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

  /// The workspace's chat mode on the server, which every message answers in, or null before it
  /// is read or when the server names one this app does not know.
  final chatMode = ValueNotifier<ChatMode?>(null);

  /// The extensions the server reads, or null when it has not said. Then the server decides.
  /// Asked again for each workspace, so a new server is asked afresh.
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

  /// The question last tested, and what it found, or null before one is tested.
  String? searched;
  List<SearchHit>? hits;
  bool searching = false;

  static const undoFor = Duration(seconds: 6);
  static const flashFor = Duration(milliseconds: 1800);

  int get onCount => files.where((f) => f.on).length;

  /// The file titled [title], or null when it is no longer in Sources.
  SourceFile? byTitle(String title) =>
      files.where((f) => f.title == title).firstOrNull;

  @override
  void dispose() {
    _chat.removeListener(_chatChanged);
    chatMode.dispose();
    _removedTimer?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }

  void _chatChanged() {
    if (_chat.activeSlug == _slug) return;
    _slug = _chat.activeSlug;
    files = const [];
    chatMode.value = null;
    problems = const [];
    loading = false;
    sending = null;
    _accepted = null;
    searched = null;
    hits = null;
    searching = false;
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
      _apply(workspace);
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

  /// Shows [workspace], already read by someone else, when it is the active one.
  void show(Workspace workspace) {
    if (workspace.slug != _slug) return;
    _apply(workspace);
    notifyListeners();
  }

  void _apply(Workspace workspace) {
    files = mergeSources(
      workspace.documents,
      _prefs.prefs.offIn(workspace.slug),
    );
    chatMode.value = ChatMode.fromServer(
      workspace.settings?.values['chatMode'],
    );
    _chat.setDocCount(workspace.slug, workspace.documents.length);
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
    var accepted = _accepted;
    try {
      accepted ??= await _api.acceptedExtensions();
      if (slug == _slug) _accepted = accepted;
    } on ApiException {
      // The server decides each file then.
    }
    final sent = await sendEach(
      _api,
      picked,
      accepted: accepted,
      onSending: (name) {
        if (slug != _slug) return;
        sending = name;
        notifyListeners();
      },
    );
    await _embedMade(slug, sent.made, [
      for (final (name, why) in sent.refused)
        Notice('Could not add $name', why),
    ]);
  }

  /// Has the server read in the web page at [url] with the details in [meta], then adds what it
  /// made.
  Future<void> addLink(String url, {DocMeta meta = const DocMeta()}) async {
    final slug = _slug;
    final link = url.trim();
    if (slug == null || link.isEmpty) return;
    final wrong = linkProblem(link);
    if (wrong != null) {
      problems = [Notice('Could not add the link', wrong)];
      notifyListeners();
      return;
    }
    await _readIn(slug, link, () => _api.uploadLink(link, meta: meta));
  }

  /// Saves [text] as a document called [title] with the details in [meta], then adds it.
  Future<void> addText(
    String title,
    String text, {
    DocMeta meta = const DocMeta(),
  }) async {
    final slug = _slug;
    final name = title.trim();
    if (slug == null || name.isEmpty || text.trim().isEmpty) return;
    await _readIn(slug, name, () => _api.uploadText(name, text, meta: meta));
  }

  /// Runs [read], which reads [name] in on the server, then adds what it made.
  Future<void> _readIn(
    String slug,
    String name,
    Future<List<DocEntry>> Function() read,
  ) async {
    sending = name;
    notifyListeners();
    try {
      await _embedMade(slug, await read(), const []);
    } on ApiException catch (error) {
      await _embedMade(slug, const [], [
        Notice('Could not add $name', error.message),
      ]);
    }
  }

  /// Embeds [made] in workspace [slug] and shows [refused], with one more notice if embedding
  /// fails.
  Future<void> _embedMade(
    String slug,
    List<DocEntry> made,
    List<Notice> refused,
  ) async {
    final problems = [...refused];
    if (made.isNotEmpty) {
      try {
        await _api.updateEmbeddings(slug, adds: [for (final d in made) d.path]);
      } on ApiException catch (error) {
        problems.add(
          Notice('Could not add the files to this workspace', error.message),
        );
      }
    }
    // The person moved to another workspace meanwhile: these notices are not about it.
    if (slug != _slug) return;
    sending = null;
    this.problems = problems;
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

  /// Finds the passages of the switched-on files that [query] would give an answer, as the
  /// workspace's own settings choose them.
  Future<void> search(String query) async {
    final slug = _slug;
    final question = query.trim();
    if (slug == null || question.isEmpty) return;
    searched = question;
    searching = true;
    notifyListeners();
    try {
      final found = await _api.searchDocs(slug, question);
      if (slug != _slug || searched != question) return;
      hits = found;
      problems = const [];
    } on ApiException catch (error) {
      if (slug != _slug || searched != question) return;
      hits = null;
      problems = [Notice('Could not test the question', error.message)];
    }
    searching = false;
    notifyListeners();
  }

  /// Puts the tested question and what it found away.
  void clearSearch() {
    searched = null;
    hits = null;
    searching = false;
    notifyListeners();
  }

  /// Sets the workspace's chat mode on the server, as its settings in the web UI do, then reads
  /// the workspace again.
  Future<void> setChatMode(ChatMode mode) async {
    final slug = _slug;
    if (slug == null || mode == chatMode.value) return;
    final was = chatMode.value;
    chatMode.value = mode;
    try {
      await _api.updateWorkspace(slug, {'chatMode': mode.name});
      if (slug != _slug) return;
      problems = const [];
    } on ApiException catch (error) {
      if (slug != _slug) return;
      chatMode.value = was;
      problems = [Notice('Could not change the chat mode', error.message)];
      notifyListeners();
      return;
    }
    await refresh();
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
      if (slug == _slug) problems = const [];
    } on ApiException catch (error) {
      if (slug == _slug) problems = [Notice(failTitle, error.message)];
    }
    await refresh();
  }
}
