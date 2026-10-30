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

/// The active workspace's Sources, which people see as Documents: the server's library, each
/// document with whether the workspace answers from it; adding documents, switching them on and
/// off, having answers read one in full, moving one to another folder and deleting one from the
/// server.
///
/// Switching a document off takes it out of the workspace on the server; it stays in the
/// library, so it stays listed. A new document goes into the folder one was last moved to.
class SourcesController extends ChangeNotifier {
  SourcesController(this._api, this._chat, this._prefs) {
    _chat.addListener(_chatChanged);
  }

  final AnythingLlmApi _api;
  final ChatController _chat;
  final PrefsController _prefs;

  /// The workspace [files] describe.
  String? _slug;

  /// The library's documents, folder by folder, each on where the workspace answers from it, and
  /// how many of them are on.
  List<SourceFile> get files => _files;
  int get onCount => files.where((f) => f.on).length;
  List<SourceFile> _files = const [];

  /// The library's folders in the server's order, those with no documents too, or none before
  /// the library is read.
  List<String> get folders => [
    for (final folder in _library.value ?? const <LibraryFolder>[]) folder.name,
  ];

  late final _workspace = ReadSlot<Workspace>(notifyListeners);
  late final _library = ReadSlot<List<LibraryFolder>>(notifyListeners);

  bool get loading => _workspace.loading || _library.loading;

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

  /// The file stored as [name] ([SourceFile.storedName]), in whichever folder, or null when the
  /// library no longer has it.
  SourceFile? byName(String name) =>
      files.where((f) => f.storedName == name).firstOrNull;

  @override
  void dispose() {
    _chat.removeListener(_chatChanged);
    chatMode.dispose();
    _flashed.take();
    super.dispose();
  }

  void _chatChanged() {
    if (_chat.activeSlug == _slug) return;
    _slug = _chat.activeSlug;
    _workspace.reset();
    _library.reset();
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

  /// Reads the active workspace's documents again, and the library with them unless [library]
  /// is false, as after a change to the workspace alone.
  Future<void> refresh({bool library = true}) async {
    final slug = _slug;
    final server = _chat.server;
    if (slug == null) return;
    bool current() => server == _chat.server && slug == _slug;
    final failed = <Notice>[];
    await Future.wait([
      _workspace.read(
        () => _api.workspace(slug),
        failTitle: 'Could not read this workspace\'s files',
        current: current,
        failed: failed.add,
      ),
      if (library)
        _library.read(
          _api.libraryFolders,
          failTitle: 'Could not read the server\'s documents',
          current: current,
          failed: failed.add,
        ),
    ]);
    if (!current()) return;
    if (failed.isNotEmpty) problems = failed;
    if (read case final workspace?) _apply(workspace);
    notifyListeners();
  }

  /// Shows [workspace], already read by someone else, when it is the active one.
  void show(Workspace workspace) {
    if (workspace.slug != _slug) return;
    // A read of Sources' own still under way is older than this one.
    _workspace.take(workspace);
    _apply(workspace);
    notifyListeners();
  }

  /// Takes what [files] and [chatMode] say from [workspace], the one [read] holds, and the
  /// library as last read.
  void _apply(Workspace workspace) {
    _files = librarySources(_library.value, workspace.documents);
    chatMode.value = ChatMode.fromServer(
      workspace.settings?.values['chatMode'],
    );
    _chat.setDocCount(workspace.slug, workspace.documents.length);
  }

  /// Switches [file] on, embedding it in the workspace, or off, taking it out. It stays in the
  /// library either way.
  Future<void> toggle(SourceFile file) => _change(
    file.on
        ? 'Could not switch ${file.title} off'
        : 'Could not switch ${file.title} on',
    (slug) => _embed(slug, file, on: !file.on),
    library: false,
  );

  /// Has the workspace's answers read [file] whole, or only its passages closest to the
  /// question, which is the server's pin. Only a file the workspace answers from has one.
  Future<void> readWhole(SourceFile file, bool whole) => _change(
    whole
        ? 'Could not have answers read ${file.title} in full'
        : 'Could not stop reading ${file.title} in full',
    (slug) => _api.pinDocument(slug, file.path, pinned: whole),
    library: false,
  );

  /// The extensions the server reads, as `.md`, asked once a workspace, or null when it would
  /// not say.
  Future<Set<String>?> acceptedTypes() async {
    if (_accepted case final known?) return known;
    final slug = _slug;
    final server = _chat.server;
    try {
      final accepted = await _api.acceptedExtensions();
      if (server == _chat.server && slug == _slug) _accepted = accepted;
      return accepted;
    } on ApiException {
      // The server decides each file then.
      return null;
    }
  }

  /// The folder a new document goes into: the one a document was last moved to, while the
  /// library still has it, or null for the server's default.
  String? get _newFolder => switch (_prefs.lastFolder) {
    final folder? when folders.contains(folder) => folder,
    _ => null,
  };

  /// Sends each file in turn into the folder used last, then embeds all the server made of them
  /// at once. Each file that cannot be added says why, and the rest still go.
  Future<void> upload(List<UploadFile> picked) async {
    final slug = _slug;
    final server = _chat.server;
    if (slug == null || picked.isEmpty) return;
    final accepted = await acceptedTypes();
    if (server != _chat.server) return;
    final sent = await sendEach(
      _api,
      picked,
      accepted: accepted,
      folder: _newFolder,
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

  /// Runs [read], which reads [name] in on the server into its default folder, then moves what
  /// it made into the folder used last and adds it.
  Future<void> _readIn(
    String slug,
    String name,
    Future<List<DocEntry>> Function() read,
  ) async {
    final server = _chat.server;
    final folder = _newFolder;
    sending = name;
    notifyListeners();
    final List<DocEntry> made;
    try {
      made = await read();
    } on ApiException catch (error) {
      await _embedMade(server, slug, const [], [
        Notice('Could not add $name', error.message),
      ]);
      return;
    }
    final notices = <Notice>[];
    await _embedMade(
      server,
      slug,
      // Moved only on the server that made them.
      folder == null || server != _chat.server
          ? made
          : await _into(folder, made, notices),
      notices,
    );
  }

  /// [made] moved into [folder], those in it already as they are; when the server will not move
  /// them they stay where they are, and [notices] says why.
  Future<List<DocEntry>> _into(
    String folder,
    List<DocEntry> made,
    List<Notice> notices,
  ) async {
    final moving = [
      for (final doc in made)
        if (doc.folder != folder) doc,
    ];
    if (moving.isEmpty) return made;
    try {
      await _api.moveDocuments([
        for (final doc in moving) (from: doc.path, to: '$folder/${doc.name}'),
      ]);
    } on ApiException catch (error) {
      notices.add(Notice('Could not put it in $folder', error.message));
      return made;
    }
    return [
      for (final doc in made)
        doc.folder == folder ? doc : DocEntry(folder: folder, name: doc.name),
    ];
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

  /// Moves [file] into the library [folder], which a new document then goes into. The server
  /// moves only a document no workspace uses, so one this workspace answers from is taken out of
  /// it first and put back once moved, read in full again if it was; one the server leaves
  /// where it is, as another workspace uses it, is put back as it was, and the notice says why.
  Future<void> move(SourceFile file, String folder) async {
    final slug = _slug;
    final server = _chat.server;
    if (slug == null || folder == file.folder) return;
    final to = '$folder/${file.storedName}';
    var moved = false;
    Notice? failed;
    try {
      if (file.on) await _embed(slug, file, on: false);
      try {
        await _api.moveDocuments([(from: file.path, to: to)]);
        moved = true;
      } on ApiException catch (error) {
        failed = Notice('Could not move ${file.title}', error.message);
      }
      if (file.on) await _putBack(slug, file, moved ? to : file.path);
    } on ApiException catch (error) {
      failed ??= Notice(
        moved
            ? 'Moved ${file.title}, but could not switch it back on'
            : 'Could not move ${file.title}',
        error.message,
      );
    }
    if (server != _chat.server) return;
    if (moved) await _prefs.setLastFolder(folder);
    if (slug != _slug) return;
    problems = [?failed];
    await refresh();
  }

  /// Embeds [file] in workspace [slug] again at [path], read in full again if it was.
  Future<void> _putBack(String slug, SourceFile file, String path) async {
    await _api.updateEmbeddings(slug, adds: [path]);
    if (file.pinned) await _api.pinDocument(slug, path, pinned: true);
  }

  /// Makes the library folder [name], or finds it there already, and reads the library again.
  /// Says why it could not, or null.
  Future<String?> createFolder(String name) async {
    final folder = name.trim();
    if (folderProblem(folder) case final problem?) return problem;
    if (folders.contains(folder)) return null;
    final slug = _slug;
    final server = _chat.server;
    try {
      await _api.createFolder(folder);
    } on ApiException catch (error) {
      return error.message;
    }
    if (server == _chat.server && slug == _slug) await refresh();
    return null;
  }

  /// Deletes [file] from the server, and so from every workspace that answers from it.
  Future<void> delete(SourceFile file) => _change(
    'Could not delete ${file.title}',
    (_) => _api.deleteDocuments([file.path]),
  );

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

  /// Runs [op] on the active workspace, then, while it is still the active one on the same
  /// server, shows why it failed, or nothing, and reads the workspace again, and the library
  /// unless [library] is false.
  Future<void> _change(
    String failTitle,
    Future<void> Function(String) op, {
    bool library = true,
  }) async {
    final slug = _slug;
    final server = _chat.server;
    if (slug == null) return;
    await changeThenRead(
      failTitle,
      () => op(slug),
      current: () => server == _chat.server && slug == _slug,
      readAgain: (failed) {
        problems = [?failed];
        return refresh(library: library);
      },
    );
  }
}
