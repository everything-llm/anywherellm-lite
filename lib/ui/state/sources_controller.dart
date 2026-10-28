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
import 'fleeting.dart';
import 'notice.dart';
import 'prefs_controller.dart';
import 'read.dart';

/// The active workspace's Sources: what it answers from, adding files, switching them on and off,
/// and removing them with a toast to undo it, which sends nothing to the server until it is
/// done with.
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

  /// The workspace's documents, switched on first, and how many of them are on. A file removed
  /// while its toast can undo it is left out.
  List<SourceFile> get files => switch (_removed) {
    null => _files,
    final removed => [
      for (final f in _files)
        if (f.path != removed.file.path) f,
    ],
  };
  int get onCount => files.where((f) => f.on).length;
  List<SourceFile> _files = const [];

  late final _workspace = ReadSlot<Workspace>(notifyListeners);

  bool get loading => _workspace.loading;

  /// The workspace as last read, from which [files] and [chatMode] come, or null before then.
  Workspace? get read => _workspace.value;

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
  SourceFile? get removed => _removed?.file;

  /// The removal the toast holds, with the workspace and server it was made on: the file is out
  /// of [files] at once and out of the workspace only once [settleRemoval] sends it.
  ({String slug, Connection? server, SourceFile file})? _removed;

  /// Whether [dispose] ran.
  bool _disposed = false;

  /// The path of the file a citation pointed at, lit up for a moment.
  String? get flashed => _flashed.value;
  late final _flashed = Fleeting<String>(flashFor, (_) => notifyListeners());

  /// The question last tested, and what it found, or null before one is tested.
  String? searched;
  List<SearchHit>? hits;
  bool searching = false;

  static const flashFor = Duration(milliseconds: 1800);

  /// The file titled [title], or null when it is no longer in Sources.
  SourceFile? byTitle(String title) =>
      files.where((f) => f.title == title).firstOrNull;

  @override
  void dispose() {
    _chat.removeListener(_chatChanged);
    _disposed = true;
    chatMode.dispose();
    // A removal still waiting is dropped, and the file stays: the app sends it as it hides.
    _removed = null;
    _flashed.take();
    super.dispose();
  }

  void _chatChanged() {
    if (_chat.activeSlug == _slug) return;
    // Another workspace leaves the toast behind: the removal it held goes now.
    unawaited(settleRemoval());
    _slug = _chat.activeSlug;
    _workspace.reset();
    _files = const [];
    chatMode.value = null;
    problems = const [];
    sending = null;
    _accepted = null;
    searched = null;
    hits = null;
    searching = false;
    notifyListeners();
    if (_slug != null) unawaited(refresh());
  }

  /// Reads the active workspace's documents again.
  Future<void> refresh() async {
    final slug = _slug;
    final server = _chat.server;
    if (slug == null) return;
    await _workspace.read(
      () => _api.workspace(slug),
      failTitle: 'Could not read this workspace\'s files',
      current: () => server == _chat.server && slug == _slug,
      kept: _apply,
      failed: (why) => problems = [why],
    );
  }

  /// Shows [workspace], already read by someone else, when it is the active one.
  void show(Workspace workspace) {
    if (workspace.slug != _slug) return;
    // A read of Sources' own still under way is older than this one.
    _workspace.take(workspace);
    _apply(workspace);
    notifyListeners();
  }

  /// Takes what [files] and [chatMode] say from [workspace], the one [read] holds.
  void _apply(Workspace workspace) {
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

  /// Takes [file] out of Sources at once, and out of the workspace on the server only once its
  /// toast is done with ([settleRemoval]): closed, replaced by another removal, left for another
  /// workspace or the sheet's closing, or the app hiding. [undo] puts it back before then, and
  /// nothing is sent.
  Future<void> remove(SourceFile file) async {
    final slug = _slug;
    if (slug == null) return;
    final before = settleRemoval();
    _removed = (slug: slug, server: _chat.server, file: file);
    notifyListeners();
    await before;
  }

  /// Puts back the file [remove] took out, while its toast shows.
  Future<void> undo() async {
    if (_removed == null) return;
    _removed = null;
    notifyListeners();
  }

  /// Sends the removal the toast holds to the workspace it was made in, then reads that
  /// workspace again while it is the active one, showing why it failed. One made on another
  /// server than the one now in use is dropped, and the file stays where it was. Given [of], it
  /// sends only that file's removal, should another have taken its place meanwhile.
  Future<void> settleRemoval({SourceFile? of}) async {
    final removed = _removed;
    if (removed == null || _disposed) return;
    if (of != null && removed.file.path != of.path) return;
    _removed = null;
    final (:slug, :server, :file) = removed;
    if (server != _chat.server) {
      notifyListeners();
      return;
    }
    // Out of the list until the read after the removal says otherwise.
    if (slug == _slug) {
      _files = [
        for (final f in _files)
          if (f.path != file.path) f,
      ];
    }
    notifyListeners();
    await _changeIn(
      slug,
      'Could not remove ${file.title}',
      () => _put(slug, file, back: false),
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
    _flashed.show(file.path);
    notifyListeners();
  }

  /// Shows a failure that is not about one file, such as a file picker that would not open.
  void report(String title, String text) {
    problems = [...problems, Notice(title, text)];
    notifyListeners();
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

  /// Runs [op] on the active workspace, then shows why it failed, or nothing, and reads the
  /// workspace again, while it is still the active one on the same server.
  Future<void> _change(
    String failTitle,
    Future<void> Function(String) op,
  ) async {
    final slug = _slug;
    if (slug == null) return;
    await _changeIn(slug, failTitle, () => op(slug));
  }

  /// Runs [op] on workspace [slug], then, while it is the active one on the same server, shows
  /// why it failed, or nothing, and reads it again.
  Future<void> _changeIn(
    String slug,
    String failTitle,
    Future<void> Function() op,
  ) async {
    final server = _chat.server;
    await changeThenRead(
      failTitle,
      op,
      current: () => server == _chat.server && slug == _slug,
      readAgain: (failed) {
        problems = [?failed];
        return refresh();
      },
    );
  }
}
