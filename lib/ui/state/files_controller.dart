import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/connection.dart';
import '../../core/copy.dart';
import '../../core/files.dart';
import '../../core/ports.dart';
import '../../core/server_models.dart';
import 'chat_controller.dart';
import 'notice.dart';
import 'settings_controller.dart';
import 'sources_controller.dart';

/// The open workspace's pages: its documents, prompt and settings under plain names, each a node
/// of the server's data as one folder tree, the node on screen and its text, and saving it.
///
/// The workspaces and their chats come from [ChatController]; this reads each workspace's prompt,
/// settings and documents itself; the server's own settings belong to `SystemController`. A new
/// server starts it afresh. A change to a workspace's documents is shown in Sources when that
/// workspace is active.
class FilesController extends ChangeNotifier {
  FilesController(this._api, this._settings, this._chat, this._sources)
    : _server = _settings.connection?.withPassword(null) {
    _settings.addListener(_serverChanged);
    _chat.addListener(_chatChanged);
    _sources.addListener(_sourcesChanged);
  }

  final AnythingLlmApi _api;
  final SettingsController _settings;
  final ChatController _chat;
  final SourcesController _sources;

  /// The connection the fields below describe.
  Connection? _server;

  /// Each workspace read on its own, with its prompt, settings and documents, by slug.
  final Map<String, Workspace> _details = {};

  /// The workspaces asked for on their own, read or not, so each is asked once.
  final Set<String> _asked = {};

  /// The tree as last built, or null when what it is built from has changed since.
  FileNode? _tree;

  bool _loaded = false;
  bool loading = false;

  /// Whether the pages have been shown, so a new server's are read as soon as its workspaces
  /// are.
  bool _wanted = false;

  /// Whether the pages are on screen, so they follow another workspace opened only while they
  /// show, and catch up when they show again.
  bool _showing = false;

  /// The path of the node on screen.
  String? selected;

  /// The selected file's text, or null while it loads or when it has none.
  String? text;

  /// The document whose text [reading] shows.
  DocBody? doc;

  /// The section the pages show.
  FilesSection get section => _section;
  FilesSection _section = FilesSection.documents;

  /// The workspace the pages last showed, so they follow when another one opens.
  String? _essentialSlug;

  /// The document whose extracted text shows in place of the documents, or null for the list.
  ({String path, String title})? get reading => _reading;
  ({String path, String title})? _reading;

  /// Counts each time [text] is read afresh, so an editor knows to drop its draft.
  int revision = 0;

  bool contentLoading = false;

  /// Why the last load or change failed.
  List<Notice> problems = const [];

  FileNode get tree =>
      _tree ??= buildTree(workspaces: _chat.workspaces, details: _details);

  FileNode? get node => selected == null ? null : nodeAt(tree, selected!);

  Workspace? detail(String slug) => _details[slug];

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
    _tree = null;
    _essentialSlug = null;
    _loaded = false;
    loading = false;
    selected = null;
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

  /// Takes the workspace Sources last read, so a change made there shows here too.
  void _sourcesChanged() {
    final read = _sources.read;
    if (!_loaded || read == null || identical(read, _details[read.slug])) {
      return;
    }
    if (!_chat.workspaces.any((w) => w.slug == read.slug)) return;
    _details[read.slug] = read;
    _tree = null;
    // The workspace's prompt or settings on show are its new ones, so a save compares against
    // what the editor shows. The path is checked first, since the node needs the tree built.
    if (selected case final path? when _under(path, read.slug)) {
      switch (node?.kind) {
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
  }

  static bool _under(String path, String slug) =>
      path == '/workspaces/$slug' || path.startsWith('/workspaces/$slug/');

  /// Waits for [read], and shows why it failed when it did.
  Future<void> _show(Future<Notice?> read) async {
    if (await read case final failed?) problems = [...problems, failed];
    notifyListeners();
  }

  /// Reads every workspace, unless already read, as the pages show.
  Future<void> ensureLoaded() async {
    _wanted = _showing = true;
    _followWorkspace();
    if (!_loaded && !loading) await load();
  }

  /// Notes that the pages are no longer on screen. It tells no listener.
  void hidden() => _showing = false;

  /// Shows [section] of the open workspace.
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

  /// Keeps the pages on the open workspace while they are on screen.
  void _followWorkspace() {
    if (!_showing || _chat.activeSlug == _essentialSlug) return;
    _essentialSlug = _chat.activeSlug;
    unawaited(_openSection());
  }

  /// Reads the text the server keeps of the document at [path], called [title], and shows it in
  /// place of the documents.
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

  /// The text the server keeps of the document at [path], or an [ApiException] when it cannot
  /// be read or the server left it out.
  Future<String> textOf(String path) async =>
      (await _api.document(path)).text ?? (throw const ApiException(noDocText));

  /// Puts the extracted text away, back to the documents.
  void closeText() {
    if (_reading == null) return;
    _reading = null;
    _clearContent();
    notifyListeners();
  }

  /// Reads every workspace on its own, all at once. A workspace that cannot be read is left
  /// without its files and says why.
  Future<void> load() async {
    if (_server == null) return;
    final server = _server;
    loading = true;
    notifyListeners();
    _asked.addAll([for (final w in _chat.workspaces) w.slug]);
    final failed = await Future.wait([
      for (final w in _chat.workspaces) _readWorkspace(w.slug),
    ]);
    if (_server != server) return;
    loading = false;
    _loaded = true;
    // Showing the node clears the problems, so the failed reads are added after it.
    // The text being read is read again with the rest, rather than put away.
    if (_reading case final reading?) {
      await viewText(reading.path, reading.title);
      if (_server != server) return;
    } else if (selected != null) {
      await _select(selected!);
      if (_server != server) return;
    }
    problems = [...failed.nonNulls, if (selected != null) ...problems];
    notifyListeners();
  }

  Future<void> _select(String path) async {
    _reading = null;
    selected = path;
    _clearContent();
    final node = this.node;
    if (node == null || node.kind.isFolder) {
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

  /// Shows a failure that is not about one node, such as a file picker that would not open.
  void report(String title, String text) {
    problems = [...problems, Notice(title, text)];
    notifyListeners();
  }

  /// Runs [op], then reads workspace [slug] again. Says whether [op] failed, worked but the
  /// workspace could not be read again, or worked and was read again.
  Future<_Changed> _change(
    String failTitle,
    Future<void> Function() op, {
    required String slug,
  }) async {
    final server = _server;
    Notice? failed;
    try {
      await op();
    } on ApiException catch (error) {
      failed = Notice(failTitle, error.message);
    }
    if (_server != server) return _Changed.failed;
    final unread = await _readWorkspace(slug);
    if (_server != server) return _Changed.failed;
    problems = [?failed, ?unread];
    notifyListeners();
    return failed != null
        ? _Changed.failed
        : unread != null
        ? _Changed.unread
        : _Changed.done;
  }

  /// Reads workspace [slug] again and tells Sources and the drawer what changed. Returns why it
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

  void _clearContent() {
    text = null;
    doc = null;
    contentLoading = false;
  }
}

/// How a change Files made went: [failed], worked but what it changed could not be read again
/// ([unread]), or worked and was read again ([done]).
enum _Changed { failed, unread, done }
