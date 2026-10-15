import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/chat.dart';
import '../../core/connection.dart';
import '../../core/ports.dart';
import '../../core/server_models.dart';
import '../../core/sources.dart';
import '../../core/system_settings.dart';
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

  /// The workspace's documents, switched on first, and how many of them are on.
  List<SourceFile> get files => _files;
  int get onCount => _files.where((f) => f.on).length;
  List<SourceFile> _files = const [];

  bool loading = false;

  /// The workspace as last read, from which [files] and [chatMode] come, or null before then.
  Workspace? read;

  /// Counts the reads started, so an answer that comes after a newer read's is dropped.
  int _reads = 0;

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
    read = null;
    _files = const [];
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
    final server = _chat.server;
    if (slug == null) return;
    final go = ++_reads;
    bool current() => server == _chat.server && slug == _slug && go == _reads;
    loading = true;
    notifyListeners();
    try {
      final workspace = await _api.workspace(slug);
      if (!current()) return;
      _apply(workspace);
    } on ApiException catch (error) {
      if (!current()) return;
      problems = [
        Notice('Could not read this workspace\'s files', error.message),
      ];
    } finally {
      if (current()) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// Shows [workspace], already read by someone else, when it is the active one.
  void show(Workspace workspace) {
    if (workspace.slug != _slug) return;
    // A read of Sources' own still under way is older than this one.
    _reads++;
    loading = false;
    _apply(workspace);
    notifyListeners();
  }

  void _apply(Workspace workspace) {
    read = workspace;
    _files = mergeSources(workspace.documents, _prefs.offIn(workspace.slug));
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
      final server = _chat.server;
      await _embed(slug, file, on: !file.on);
      // The switched-off list is kept by server: another one now has its own.
      if (server != _chat.server) return;
      await _remember(slug, file, off: file.on);
    },
  );

  /// Sends each file in turn, then embeds all the server made of them at once. Each file that
  /// cannot be added says why, and the rest still go.
  Future<void> upload(List<UploadFile> picked) async {
    final slug = _slug;
    final server = _chat.server;
    if (slug == null || picked.isEmpty) return;
    var accepted = _accepted;
    try {
      accepted ??= await _api.acceptedExtensions();
      if (server == _chat.server && slug == _slug) _accepted = accepted;
    } on ApiException {
      // The server decides each file then.
    }
    if (server != _chat.server) return;
    final sent = await sendEach(
      _api,
      picked,
      accepted: accepted,
      shouldContinue: () => server == _chat.server,
      onSending: (name) {
        if (slug != _slug) return;
        sending = name;
        notifyListeners();
      },
    );
    await _embedMade(server, slug, sent.made, [
      for (final (name, why) in sent.refused)
        Notice('Could not add $name', why),
    ]);
  }

  /// Has the server read in the web page at [url] with the details in [meta], then adds what it
  /// made. Answers at once whether it took [url]: one that is not a link is refused and says why.
  bool addLink(String url, {DocMeta meta = const DocMeta()}) {
    final slug = _slug;
    final link = url.trim();
    if (slug == null || link.isEmpty) return false;
    if (linkProblem(link) case final wrong?) {
      problems = [Notice('Could not add the link', wrong)];
      notifyListeners();
      return false;
    }
    unawaited(_readIn(slug, link, () => _api.uploadLink(link, meta: meta)));
    return true;
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
    final server = _chat.server;
    sending = name;
    notifyListeners();
    try {
      await _embedMade(server, slug, await read(), const []);
    } on ApiException catch (error) {
      await _embedMade(server, slug, const [], [
        Notice('Could not add $name', error.message),
      ]);
    }
  }

  /// Embeds [made] in workspace [slug] and shows [refused], with one more notice if embedding
  /// fails.
  Future<void> _embedMade(
    Connection? server,
    String slug,
    List<DocEntry> made,
    List<Notice> refused,
  ) async {
    if (server != _chat.server) return;
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
    if (server != _chat.server || slug != _slug) return;
    sending = null;
    this.problems = problems;
    await refresh();
  }

  /// Takes [file] out of Sources. [undo] puts it back for a few seconds after.
  Future<void> remove(SourceFile file) {
    final server = _chat.server;
    return _change('Could not remove ${file.title}', (slug) async {
      await _put(slug, file, back: false);
      if (server != _chat.server || slug != _slug) return;
      _clearRemoved();
      removed = file;
      _removedTimer = Timer(undoFor, () {
        removed = null;
        notifyListeners();
      });
    });
  }

  Future<void> undo() async {
    final file = removed;
    if (file == null) return;
    _clearRemoved();
    await _change(
      'Could not put ${file.title} back',
      (slug) => _put(slug, file, back: true),
    );
  }

  /// Takes [file] out of the workspace's answers, or puts it [back]: a switched-on file by its
  /// embedding, a switched-off one by the note of it in the prefs.
  Future<void> _put(String slug, SourceFile file, {required bool back}) =>
      file.on ? _embed(slug, file, on: back) : _remember(slug, file, off: back);

  /// Finds the passages of the switched-on files that [query] would give an answer, as the
  /// workspace's own settings choose them.
  Future<void> search(String query) async {
    final slug = _slug;
    final server = _chat.server;
    final question = query.trim();
    if (slug == null || question.isEmpty) return;
    bool current() =>
        server == _chat.server && slug == _slug && searched == question;
    searched = question;
    searching = true;
    notifyListeners();
    try {
      final found = await _api.searchDocs(slug, question);
      if (!current()) return;
      hits = found;
      problems = const [];
    } on ApiException catch (error) {
      if (!current()) return;
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
    final server = _chat.server;
    if (slug == null || mode == chatMode.value) return;
    final was = chatMode.value;
    chatMode.value = mode;
    try {
      await _api.updateWorkspace(slug, {'chatMode': mode.name});
      if (server != _chat.server || slug != _slug) return;
      problems = const [];
    } on ApiException catch (error) {
      if (server != _chat.server || slug != _slug) return;
      chatMode.value = was;
      problems = [Notice('Could not change the chat mode', error.message)];
      notifyListeners();
      return;
    }
    await refresh();
  }

  /// The provider and model the workspace answers with, null where it uses the system's.
  String? get chatProvider => _own('chatProvider');
  String? get chatModel => _own('chatModel');

  String? _own(String key) =>
      switch (settingText(read?.settings?.values, key).trim()) {
        '' => null,
        final text => text,
      };

  /// Makes the workspace answer with [provider] and [model], null for the system's, the same
  /// columns the workspace's answer settings write. Says why the server refused, or null.
  Future<String?> setChatModel(String? provider, String? model) async {
    final slug = _slug;
    final server = _chat.server;
    if (slug == null) return 'No workspace is open.';
    try {
      await _api.updateWorkspace(slug, {
        'chatProvider': provider,
        'chatModel': model,
      });
    } on ApiException catch (error) {
      return error.message;
    }
    if (server == _chat.server && slug == _slug) await refresh();
    return null;
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
        for (final doc in _prefs.offIn(slug))
          if (doc.path != file.path) doc,
        if (off) file.asOff,
      ]);

  Future<void> _change(
    String failTitle,
    Future<void> Function(String) op,
  ) async {
    final slug = _slug;
    final server = _chat.server;
    if (slug == null) return;
    try {
      await op(slug);
      if (server == _chat.server && slug == _slug) problems = const [];
    } on ApiException catch (error) {
      if (server == _chat.server && slug == _slug) {
        problems = [Notice(failTitle, error.message)];
      }
    }
    await refresh();
  }
}
