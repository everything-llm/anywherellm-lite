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
/// a node allows.
///
/// The workspaces and their chats come from [ChatController]; this reads each workspace's prompt,
/// settings and documents, the library and the model settings itself. A new server starts it
/// afresh. A change to a workspace's documents is shown in Sources when that workspace is active.
class FilesController extends ChangeNotifier {
  FilesController(
    this._api,
    this._settings,
    this._chat,
    this._prefs,
    this._sources,
  ) : _server = _settings.connection {
    _settings.addListener(_serverChanged);
    _chat.addListener(_chatChanged);
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

  final Set<String> _expanded = {'/workspaces', '/library'};

  /// The path of the node on screen.
  String? selected;

  /// The selected file's text, or null while it loads or when it has none.
  String? text;

  /// The selected library document, or the one a workspace link points at.
  DocBody? doc;

  /// Counts each time [text] is read afresh, so an editor knows to drop its draft.
  int revision = 0;

  bool contentLoading = false;

  /// The file being sent now, or null.
  String? sending;

  /// Whether every chat is being exported now.
  bool exporting = false;

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
    super.dispose();
  }

  void _serverChanged() {
    if (_settings.connection == _server) return;
    _server = _settings.connection;
    _details.clear();
    _asked.clear();
    _library = null;
    _accepted = null;
    _tree = null;
    _loaded = false;
    selected = null;
    _clearContent();
    problems = const [];
    exporting = false;
    notifyListeners();
  }

  /// Follows the workspaces: one made after [load] is read on its own too, and a deleted one is
  /// forgotten.
  void _chatChanged() {
    _tree = null;
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
    if (!_loaded) return;
    for (final w in _chat.workspaces) {
      if (_asked.add(w.slug)) unawaited(_readAndShow(w.slug));
    }
  }

  static bool _under(String path, String slug) =>
      path == '/workspaces/$slug' || path.startsWith('/workspaces/$slug/');

  Future<void> _readAndShow(String slug) async {
    await _readWorkspace(slug);
    notifyListeners();
  }

  /// Reads every workspace, the library and the model settings, unless already read.
  Future<void> ensureLoaded() async {
    if (!_loaded && !loading) await load();
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
    problems = failed.nonNulls.toList();
    notifyListeners();
    if (selected != null) await select(selected!);
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

  /// Shows the node at [path], reading its text or document.
  Future<void> select(String path) async {
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
      NodeKind.models => (modelsText(await _api.systemSettings()), null),
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
    final ok = await _change(
      'Could not save ${node.name}',
      () => _api.updateWorkspace(slug, fields),
      slug: slug,
    );
    if (ok) await select(node.path);
    return ok;
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
    try {
      _accepted ??= await _api.acceptedExtensions();
    } on ApiException {
      // The server decides each file then.
    }
    final sent = await sendEach(
      _api,
      picked,
      accepted: _accepted,
      folder: folder,
      onSending: (name) {
        sending = name;
        notifyListeners();
      },
    );
    if (_server != server) return;
    sending = null;
    await _readLibrary();
    problems = [
      for (final (name, why) in sent.refused)
        Notice('Could not add $name', why),
    ];
    notifyListeners();
  }

  Future<void> createFolder(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    final ok = await _change(
      'Could not make the folder',
      () => _api.createFolder(clean),
      library: true,
    );
    if (ok) _expanded.add(libraryPath(clean));
  }

  /// Moves the library document at [path] into [folder], and says so when the server kept it
  /// where it was, as it does with a document a workspace uses.
  Future<void> move(String path, String folder) async {
    final to = '$folder/${docName(path)}';
    if (to == path) return;
    final ok = await _change(
      'Could not move the document',
      () => _api.moveDocuments([(path, to)]),
      library: true,
    );
    if (!ok) return;
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
    final ok = await _change(
      'Could not delete the document',
      () => _api.removeDocuments([path]),
      slugs: [for (final w in usersOf(path)) w.slug],
      library: true,
    );
    if (!ok) return;
    final active = _chat.activeSlug;
    final shownOff =
        active != null && _prefs.prefs.offIn(active).any((d) => d.path == path);
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
    final ok = await _change(
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
    if (!ok) return;
    final active = _chat.activeSlug;
    final shownOff =
        active != null &&
        _prefs.prefs.offIn(active).any((d) => paths.contains(d.path));
    await _prefs.forgetDocs(paths);
    if (shownOff) unawaited(_sources.refresh());
    _expanded.remove(libraryPath(name));
    await select('/library');
  }

  /// Every chat on the server in [format], or null when the server would not give them, which
  /// [problems] then says.
  Future<List<int>?> exportChats(ChatExport format) async {
    final server = _server;
    exporting = true;
    notifyListeners();
    List<int>? bytes;
    Notice? failed;
    try {
      bytes = await _api.exportChats(format);
    } on ApiException catch (error) {
      failed = Notice('Could not export the chats', error.message);
    }
    if (_server != server) return null;
    problems = [?failed];
    exporting = false;
    notifyListeners();
    return bytes;
  }

  /// Shows a failure that is not about one node, such as a file picker that would not open.
  void report(String title, String text) {
    problems = [...problems, Notice(title, text)];
    notifyListeners();
  }

  /// Runs [op], then reads again what it changed: workspace [slug], the workspaces in [slugs],
  /// and the library when [library]. Returns whether [op] succeeded.
  Future<bool> _change(
    String failTitle,
    Future<void> Function() op, {
    String? slug,
    List<String> slugs = const [],
    bool library = false,
  }) async {
    final server = _server;
    var ok = true;
    try {
      await op();
      problems = const [];
    } on ApiException catch (error) {
      problems = [Notice(failTitle, error.message)];
      ok = false;
    }
    if (_server != server) return false;
    await Future.wait([
      for (final s in {?slug, ...slugs}) _readWorkspace(s),
      if (library) _readLibrary(),
    ]);
    notifyListeners();
    return ok;
  }

  /// Reads workspace [slug] again and tells Sources and the sidebar what changed. Returns why it
  /// could not, or null; the tree then keeps what it last read.
  Future<Notice?> _readWorkspace(String slug) async {
    try {
      final w = await _api.workspace(slug);
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
    try {
      _library = await _api.libraryFolders();
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
