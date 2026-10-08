import 'dart:collection';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/connection.dart';
import '../../core/files.dart';
import '../../core/ports.dart';
import '../../core/server_models.dart';
import '../../core/upload.dart';
import 'chat_controller.dart';
import 'notice.dart';
import 'prefs_controller.dart';
import 'settings_controller.dart';
import 'sources_controller.dart';

/// Files: the server's data as one folder tree, the node on screen and its text, and the changes
/// a node allows. Its Essentials view shows the open workspace's documents, prompt and settings
/// under plain names, each the same node as in the tree.
///
/// The workspaces and their chats come from [ChatController]; this reads each workspace's prompt,
/// settings and documents and the library itself; the server's own settings belong to
/// `SystemController`. A new server starts it afresh. A change to a workspace's documents is
/// shown in Sources when that workspace is active.
class FilesController extends ChangeNotifier {
  FilesController(
    this._api,
    this._settings,
    this._chat,
    this._prefs,
    this._sources,
  ) : _server = _settings.connection?.withPassword(null) {
    _settings.addListener(_serverChanged);
    _chat.addListener(_chatChanged);
    _sources.addListener(_sourcesChanged);
  }

  final AnythingLlmApi _api;
  final SettingsController _settings;
  final ChatController _chat;
  final PrefsController _prefs;
  final SourcesController _sources;

  /// The connection the fields below describe.
  Connection? _server;

  /// Each workspace read on its own, with its prompt, settings and documents, by slug.
  final Map<String, Workspace> _details = {};

  /// The workspaces asked for on their own, read or not, so each is asked once.
  final Set<String> _asked = {};
  List<LibraryFolder>? _library;

  /// The extensions the server reads, asked once per server, or null when it has not said.
  Set<String>? _accepted;

  /// The tree as last built, or null when what it is built from has changed since.
  FileNode? _tree;

  bool _loaded = false;
  bool loading = false;

  /// Whether Files has been shown, so a new server's files are read as soon as its workspaces
  /// are.
  bool _wanted = false;

  final Set<String> _expanded = {'/workspaces', '/library'};

  /// The path of the node on screen.
  String? selected;

  /// The selected file's text, or null while it loads or when it has none.
  String? text;

  /// The selected library document, the one a workspace link points at, or the one whose text
  /// [reading] shows.
  DocBody? doc;

  /// Whether the sidebar lists the Essentials view's sections rather than the whole tree. It
  /// starts on, and holds for this run only.
  bool get essentials => _essentials;
  bool _essentials = true;

  /// The section the Essentials view shows.
  FilesSection get section => _section;
  FilesSection _section = FilesSection.documents;

  /// The workspace the Essentials view last showed, so it follows when another one opens.
  String? _essentialSlug;

  /// The document whose extracted text the Essentials view shows in place of its documents,
  /// or null for the list.
  ({String path, String title})? get reading => _reading;
  ({String path, String title})? _reading;

  /// Counts each time [text] is read afresh, so an editor knows to drop its draft.
  int revision = 0;

  bool contentLoading = false;

  /// Whether a workspace's `settings.json` shows as JSON rather than the form. It holds while
  /// the same file is read afresh, as after a save.
  bool get settingsAsJson => _settingsAsJson;
  bool _settingsAsJson = false;

  /// The file being sent now, or null.
  String? sending;

  /// Why the last load or change failed.
  List<Notice> problems = const [];

  /// The folders shown open, by path.
  Set<String> get expanded => UnmodifiableSetView(_expanded);

  FileNode get tree => _tree ??= buildTree(
    workspaces: _chat.workspaces,
    threadsOf: _chat.threadsOf,
    details: _details,
    library: _library,
  );

  FileNode? get node => selected == null ? null : nodeAt(tree, selected!);

  Workspace? detail(String slug) => _details[slug];

  List<LibraryFolder> get library => _library ?? const [];

  /// The documents in library folder [name].
  List<LibraryFile> folderDocs(String name) => [
    for (final f in library)
      if (f.name == name) ...f.files,
  ];

  /// The workspaces, among those read, that use the library document at [path].
  List<Workspace> usersOf(String path) => [
    for (final w in _details.values)
      if (w.documents.any((d) => d.path == path)) w,
  ];

  /// The document at [path] as workspace [slug] holds it, or null.
  WorkspaceDoc? docIn(String slug, String path) =>
      _details[slug]?.documents.where((d) => d.path == path).firstOrNull;

  @override
  void dispose() {
    _settings.removeListener(_serverChanged);
    _chat.removeListener(_chatChanged);
    _sources.removeListener(_sourcesChanged);
    super.dispose();
  }

  void _serverChanged() {
    // A password saved or forgotten is the same server.
    final now = _settings.connection?.withPassword(null);
    if (now == _server) return;
    _server = now;
    _details.clear();
    _asked.clear();
    _library = null;
    _accepted = null;
    _tree = null;
    _essentialSlug = null;
    _loaded = false;
    loading = false;
    sending = null;
    selected = null;
    _settingsAsJson = false;
    _clearContent();
    problems = const [];
    notifyListeners();
  }

  /// Follows the workspaces: one made after [load] is read on its own too, and a deleted one is
  /// forgotten.
  void _chatChanged() {
    _tree = null;
    _followWorkspace();
    final gone = _details.keys.followedBy(_asked).toSet().difference({
      for (final w in _chat.workspaces) w.slug,
    });
    for (final slug in gone) {
      _details.remove(slug);
      _asked.remove(slug);
      _expanded.removeWhere((path) => _under(path, slug));
      if (selected != null && _under(selected!, slug)) {
        selected = '/workspaces';
        _clearContent();
      }
    }
    notifyListeners();
    if (!_loaded) {
      if (_wanted && !loading && !_chat.loading && _server != null) {
        unawaited(load());
      }
      return;
    }
    for (final w in _chat.workspaces) {
      if (_asked.add(w.slug)) unawaited(_show(_readWorkspace(w.slug)));
    }
  }

  /// Takes the workspace Sources last read, so a change made there shows here too. A document
  /// it uses that the library does not list was added there, so the library is read again.
  void _sourcesChanged() {
    final read = _sources.read;
    if (!_loaded || read == null || identical(read, _details[read.slug])) {
      return;
    }
    if (!_chat.workspaces.any((w) => w.slug == read.slug)) return;
    final had = {for (final d in _details[read.slug]?.documents ?? []) d.path};
    _details[read.slug] = read;
    _tree = null;
    // The workspace's prompt or settings on show are its new ones, so a save compares against
    // what the editor shows.
    if (node case final shown? when shown.slug == read.slug) {
      switch (shown.kind) {
        case NodeKind.prompt:
          text = read.prompt ?? '';
          revision++;
        case NodeKind.settings when read.settings != null:
          text = settingsText(read.settings!);
          revision++;
        default:
      }
    }
    notifyListeners();
    final added = [
      for (final d in read.documents)
        if (!had.contains(d.path)) d.path,
    ];
    if (added.isEmpty) return;
    final listed = {
      for (final f in library)
        for (final d in f.files) d.path,
    };
    if (!added.every(listed.contains)) unawaited(_show(_readLibrary()));
  }

  static bool _under(String path, String slug) =>
      path == '/workspaces/$slug' || path.startsWith('/workspaces/$slug/');

  /// Waits for [read], and shows why it failed when it did.
  Future<void> _show(Future<Notice?> read) async {
    if (await read case final failed?) problems = [...problems, failed];
    notifyListeners();
  }

  /// Reads every workspace and the library, unless already read.
  Future<void> ensureLoaded() async {
    _wanted = true;
    _followWorkspace();
    if (!_loaded && !loading) await load();
  }

  /// Shows the Essentials view, on the section last shown, or the whole tree, on the node the
  /// Essentials view showed.
  void showEssentials(bool on) {
    if (on == _essentials) return;
    _essentials = on;
    if (on) {
      _essentialSlug = _chat.activeSlug;
      unawaited(_openSection());
      return;
    }
    _reading = null;
    if (selected case final path?) _expanded.addAll(ancestorsOf(path));
    notifyListeners();
  }

  /// Shows [section] of the open workspace in the Essentials view.
  Future<void> openSection(FilesSection section) {
    _section = section;
    _essentialSlug = _chat.activeSlug;
    return _openSection();
  }

  Future<void> _openSection() {
    final path = switch (_essentialSlug) {
      final slug? => _section.pathIn(slug),
      null => null,
    };
    if (path != null) return _select(path);
    _reading = null;
    selected = null;
    _clearContent();
    notifyListeners();
    return Future.value();
  }

  /// Keeps the Essentials view on the open workspace once Files has been shown.
  void _followWorkspace() {
    if (!_essentials || !_wanted || _chat.activeSlug == _essentialSlug) return;
    _essentialSlug = _chat.activeSlug;
    unawaited(_openSection());
  }

  /// Reads the text the server keeps of the document at [path], called [title], and shows it in
  /// place of the Essentials view's documents.
  Future<void> viewText(String path, String title) async {
    final reading = _reading = (path: path, title: title);
    doc = null;
    contentLoading = true;
    notifyListeners();
    final server = _server;
    try {
      final read = await _api.document(path);
      if (_reading != reading || _server != server) return;
      doc = read;
      problems = const [];
    } on ApiException catch (error) {
      if (_reading != reading || _server != server) return;
      problems = [Notice('Could not read $title', error.message)];
    }
    contentLoading = false;
    notifyListeners();
  }

  /// Puts the extracted text away, back to the documents.
  void closeText() {
    if (_reading == null) return;
    _reading = null;
    _clearContent();
    notifyListeners();
  }

  /// Reads every workspace on its own and the library, all at once. A workspace that cannot be
  /// read is left without its files and says why.
  Future<void> load() async {
    if (_server == null) return;
    final server = _server;
    loading = true;
    notifyListeners();
    _asked.addAll([for (final w in _chat.workspaces) w.slug]);
    final failed = await Future.wait([
      for (final w in _chat.workspaces) _readWorkspace(w.slug),
      _readLibrary(),
    ]);
    if (_server != server) return;
    loading = false;
    _loaded = true;
    // Showing the node clears the problems, so the failed reads are added after it.
    if (selected != null) {
      await _select(selected!);
      if (_server != server) return;
    }
    problems = [...failed.nonNulls, if (selected != null) ...problems];
    notifyListeners();
  }

  void toggle(String path) {
    if (!_expanded.remove(path)) _expanded.add(path);
    notifyListeners();
  }

  /// Opens every folder above [path], then shows it.
  Future<void> reveal(String path) {
    _expanded.addAll(ancestorsOf(path));
    return select(path);
  }

  /// Shows the node at [path] in the whole tree, reading its text or document.
  Future<void> select(String path) {
    if (_essentials) {
      _essentials = false;
      _expanded.addAll(ancestorsOf(path));
    }
    return _select(path);
  }

  Future<void> _select(String path) async {
    if (path != selected) _settingsAsJson = false;
    _reading = null;
    selected = path;
    _clearContent();
    final node = this.node;
    if (node == null || node.kind.isFolder || node.kind == NodeKind.locked) {
      notifyListeners();
      return;
    }
    contentLoading = true;
    notifyListeners();
    final server = _server;
    try {
      final (text, doc) = await _content(node);
      if (selected != path || _server != server) return;
      this.text = text;
      this.doc = doc;
      revision++;
      problems = const [];
    } on ApiException catch (error) {
      if (selected != path || _server != server) return;
      problems = [Notice('Could not read ${node.name}', error.message)];
    }
    contentLoading = false;
    notifyListeners();
  }

  void showSettingsAsJson(bool json) {
    if (_settingsAsJson == json) return;
    _settingsAsJson = json;
    notifyListeners();
  }

  Future<(String?, DocBody?)> _content(FileNode node) async {
    final detail = node.slug == null ? null : _details[node.slug];
    return switch (node.kind) {
      NodeKind.prompt => (detail?.prompt ?? '', null),
      NodeKind.settings => (settingsText(detail!.settings!), null),
      NodeKind.chatLog => (
        chatMarkdown(
          _chat
                  .threadsOf(node.slug!)
                  .where((t) => t.slug == node.ref)
                  .firstOrNull
                  ?.name ??
              node.name,
          await _api.history(node.slug!, node.ref!),
        ),
        null,
      ),
      NodeKind.libraryDoc ||
      NodeKind.docLink => (null, await _api.document(node.ref!)),
      _ => (null, null),
    };
  }

  /// Saves [draft] as the selected prompt or settings file. Returns whether it was saved.
  Future<bool> save(String draft) async {
    final node = this.node;
    final slug = node?.slug;
    if (node == null || slug == null || !node.kind.editable) return false;
    final Map<String, Object?> fields;
    try {
      fields = node.kind == NodeKind.prompt
          // An empty prompt is no prompt, so the default applies again.
          ? {'openAiPrompt': draft.trim().isEmpty ? null : draft}
          : parseSettings(draft, _details[slug]!.settings!);
    } on ApiException catch (error) {
      problems = [Notice('Could not save ${node.name}', error.message)];
      notifyListeners();
      return false;
    }
    if (fields.isEmpty) return true;
    final changed = await _change(
      'Could not save ${node.name}',
      () => _api.updateWorkspace(slug, fields),
      slug: slug,
    );
    // When the workspace could not be read again, the draft stays on screen with why.
    if (changed == _Changed.done) await _select(node.path);
    return changed != _Changed.failed;
  }

  /// Embeds the library document at [path] in workspace [slug].
  Future<void> attach(String slug, String path) => _change(
    'Could not attach the document',
    () => _api.updateEmbeddings(slug, adds: [path]),
    slug: slug,
  );

  /// Takes the document at [path] out of workspace [slug]. It stays in the library.
  Future<void> detach(String slug, String path) async {
    await _change(
      'Could not detach the document',
      () => _api.updateEmbeddings(slug, deletes: [path]),
      slug: slug,
    );
    if (selected == docLinkPath(slug, path)) await select(docsPath(slug));
  }

  Future<void> pin(String slug, String path, {required bool pinned}) => _change(
    pinned ? 'Could not pin the document' : 'Could not unpin the document',
    () => _api.pinDocument(slug, path, pinned: pinned),
    slug: slug,
  );

  /// Sends each file into library [folder] in turn. Each file that cannot be added says why,
  /// and the rest still go.
  Future<void> upload(String folder, List<UploadFile> picked) async {
    if (picked.isEmpty) return;
    final server = _server;
    var accepted = _accepted;
    try {
      accepted ??= await _api.acceptedExtensions();
      if (_server == server) _accepted = accepted;
    } on ApiException {
      // The server decides each file then.
    }
    if (_server != server) return;
    final sent = await sendEach(
      _api,
      picked,
      accepted: accepted,
      folder: folder,
      shouldContinue: () => _server == server,
      onSending: (name) {
        sending = name;
        notifyListeners();
      },
    );
    if (_server != server) return;
    sending = null;
    final unread = await _readLibrary();
    problems = [
      for (final (name, why) in sent.refused)
        Notice('Could not add $name', why),
      ?unread,
    ];
    notifyListeners();
  }

  Future<void> createFolder(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    final changed = await _change(
      'Could not make the folder',
      () => _api.createFolder(clean),
      library: true,
    );
    if (changed != _Changed.failed) _expanded.add(libraryPath(clean));
  }

  /// Moves the library document at [path] into [folder], and says so when the server kept it
  /// where it was, as it does with a document a workspace uses.
  Future<void> move(String path, String folder) async {
    final to = '$folder/${docName(path)}';
    if (to == path) return;
    final changed = await _change(
      'Could not move the document',
      () => _api.moveDocuments([(path, to)]),
      library: true,
    );
    // A library that could not be read again says nothing about where the document is.
    if (changed != _Changed.done) return;
    if (library.any((f) => f.files.any((d) => d.path == path))) {
      problems = [
        const Notice(
          'The server kept the document where it was',
          'It does not move a document a workspace uses. Detach it first.',
        ),
      ];
      notifyListeners();
      return;
    }
    await reveal(libraryPath(to));
  }

  /// Deletes the library document at [path], which takes it out of every workspace, and forgets
  /// it wherever it was switched off in Sources.
  Future<void> deleteFromLibrary(String path) async {
    final changed = await _change(
      'Could not delete the document',
      () => _api.removeDocuments([path]),
      slugs: [for (final w in usersOf(path)) w.slug],
      library: true,
    );
    if (changed == _Changed.failed) return;
    final active = _chat.activeSlug;
    final shownOff =
        active != null && _prefs.offIn(active).any((d) => d.path == path);
    await _prefs.forgetDocs([path]);
    if (shownOff) unawaited(_sources.refresh());
    if (selected == libraryPath(path)) {
      await select(libraryPath(docFolder(path)));
    }
  }

  /// Deletes library folder [name] with its documents, which takes them out of every workspace,
  /// and forgets them wherever they were switched off in Sources.
  Future<void> deleteFolder(String name) async {
    final paths = [for (final d in folderDocs(name)) d.path];
    final changed = await _change(
      'Could not delete the folder',
      () => _api.removeFolder(name),
      slugs: [
        ...{
          for (final path in paths)
            for (final w in usersOf(path)) w.slug,
        },
      ],
      library: true,
    );
    if (changed == _Changed.failed) return;
    final active = _chat.activeSlug;
    final shownOff =
        active != null &&
        _prefs.offIn(active).any((d) => paths.contains(d.path));
    await _prefs.forgetDocs(paths);
    if (shownOff) unawaited(_sources.refresh());
    _expanded.remove(libraryPath(name));
    await select('/library');
  }

  /// Shows a failure that is not about one node, such as a file picker that would not open.
  void report(String title, String text) {
    problems = [...problems, Notice(title, text)];
    notifyListeners();
  }

  /// Runs [op], then reads again what it changed: workspace [slug], the workspaces in [slugs],
  /// and the library when [library]. Says whether [op] failed, worked but what it changed could
  /// not be read again, or worked and was read again.
  Future<_Changed> _change(
    String failTitle,
    Future<void> Function() op, {
    String? slug,
    List<String> slugs = const [],
    bool library = false,
  }) async {
    final server = _server;
    Notice? failed;
    try {
      await op();
    } on ApiException catch (error) {
      failed = Notice(failTitle, error.message);
    }
    if (_server != server) return _Changed.failed;
    final unread = await Future.wait([
      for (final s in {?slug, ...slugs}) _readWorkspace(s),
      if (library) _readLibrary(),
    ]);
    if (_server != server) return _Changed.failed;
    problems = [?failed, ...unread.nonNulls];
    notifyListeners();
    return failed != null
        ? _Changed.failed
        : unread.any((n) => n != null)
        ? _Changed.unread
        : _Changed.done;
  }

  /// Reads workspace [slug] again and tells Sources and the sidebar what changed. Returns why it
  /// could not, or null; the tree then keeps what it last read.
  Future<Notice?> _readWorkspace(String slug) async {
    final server = _server;
    try {
      final w = await _api.workspace(slug);
      if (_server != server) return null;
      _details[slug] = w;
      _tree = null;
      if (slug == _chat.activeSlug) {
        _sources.show(w);
      } else {
        _chat.setDocCount(slug, w.documents.length);
      }
      return null;
    } on ApiException catch (error) {
      return Notice('Could not read $slug', error.message);
    }
  }

  /// Reads the library again. Returns why it could not, or null.
  Future<Notice?> _readLibrary() async {
    final server = _server;
    try {
      final read = await _api.libraryFolders();
      if (_server != server) return null;
      _library = read;
      _tree = null;
      return null;
    } on ApiException catch (error) {
      return Notice('Could not read the library', error.message);
    }
  }

  void _clearContent() {
    text = null;
    doc = null;
    contentLoading = false;
  }
}

/// How a change Files made went: [failed], worked but what it changed could not be read again
/// ([unread]), or worked and was read again ([done]).
enum _Changed { failed, unread, done }
