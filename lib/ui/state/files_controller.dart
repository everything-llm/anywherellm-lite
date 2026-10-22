import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/copy.dart';
import '../../core/files.dart';
import '../../core/ports.dart';
import '../../core/server_models.dart';
import 'chat_controller.dart';
import 'follows_server.dart';
import 'notice.dart';
import 'read.dart';
import 'settings_controller.dart';
import 'sources_controller.dart';

/// The open workspace's pages: its prompt and its answer settings, the text of one of its
/// documents, and saving them.
///
/// The workspace comes as [SourcesController] last read it, and as this reads it again after a
/// change; the server's own settings belong to `SystemController`. A new server starts it
/// afresh. A change to a workspace's documents is shown in Sources when that workspace is
/// active.
class FilesController extends ChangeNotifier with FollowsServer {
  FilesController(
    this._api,
    SettingsController settings,
    this._chat,
    this._sources,
  ) {
    followServer(settings);
    _chat.addListener(_chatChanged);
    _sources.addListener(_sourcesChanged);
    _sourcesChanged();
  }

  final AnythingLlmApi _api;
  final ChatController _chat;
  final SourcesController _sources;

  /// Each workspace as last read, with its prompt, settings and documents, by slug.
  final Map<String, Workspace> _details = {};

  /// Whether Sources was reading when it last told this, so a read ending is passed on.
  bool _sourcesLoading = false;

  /// Whether the pages are on screen, so they follow another workspace opened only while they
  /// show, and catch up when they show again.
  bool _showing = false;

  /// The section the pages show.
  FilesSection get section => _section;
  FilesSection _section = FilesSection.instructions;

  /// The workspace the pages show, so they follow when another one opens.
  String? get workspace => _pagesSlug;
  String? _pagesSlug;

  /// The document whose extracted text shows in place of the page, or null for the page.
  ({String path, String title})? get reading => _reading;
  ({String path, String title})? _reading;

  late final _text = ReadSlot<DocBody>(notifyListeners);

  /// The text of the documents read lately, by path, the oldest first, so going back to one
  /// reads nothing again.
  final _texts = <String, String>{};

  /// How many documents' text [_texts] keeps.
  static const textsKept = 8;

  /// The text of the document [reading] shows, or null while it loads or when it has none.
  String? get text => _text.value?.text;

  /// Counts each time the workspace the pages show is read afresh, so an editor knows to drop
  /// its draft.
  int revision = 0;

  bool get contentLoading => _text.loading;

  /// Whether the workspace the pages show is still being read.
  bool get loading => _pagesSlug != null && _sources.loading;

  /// Why the last load or change failed.
  List<Notice> problems = const [];

  Workspace? detail(String slug) => _details[slug];

  @override
  void dispose() {
    _chat.removeListener(_chatChanged);
    _sources.removeListener(_sourcesChanged);
    super.dispose();
  }

  @override
  void serverChanged(_) {
    _details.clear();
    _pagesSlug = null;
    _reading = null;
    _text.reset();
    _texts.clear();
    problems = const [];
    notifyListeners();
  }

  /// Follows the open workspace, and forgets a deleted one.
  void _chatChanged() {
    _followWorkspace();
    final slugs = {for (final w in _chat.workspaces) w.slug};
    final before = _details.length;
    _details.removeWhere((slug, _) => !slugs.contains(slug));
    if (_details.length != before) notifyListeners();
  }

  /// Takes the workspace Sources last read, so a change made there shows here too.
  void _sourcesChanged() {
    final read = _sources.read;
    final ended = _sourcesLoading && !_sources.loading;
    _sourcesLoading = _sources.loading;
    if (read != null && !identical(read, _details[read.slug])) {
      _take(read);
    } else if (!ended) {
      return;
    }
    notifyListeners();
  }

  /// Keeps [read] as its workspace's, the one the pages show afresh when it is that one.
  void _take(Workspace read) {
    _details[read.slug] = read;
    if (read.slug == _pagesSlug) revision++;
  }

  /// Follows the open workspace, as the pages show.
  Future<void> ensureLoaded() async {
    _showing = true;
    _followWorkspace();
  }

  /// Notes that the pages are on screen, and follows the open workspace after the frame that
  /// builds them, since that tells the listeners at once.
  void shown() {
    _showing = true;
    afterFrame(_followWorkspace);
  }

  /// Notes that the pages are no longer on screen. It tells no listener.
  void hidden() => _showing = false;

  /// Shows [section] of the open workspace.
  Future<void> openSection(FilesSection section) async {
    _section = section;
    _pagesSlug = _chat.activeSlug;
    _reading = null;
    _text.reset();
    problems = const [];
    notifyListeners();
  }

  /// Keeps the pages on the open workspace while they are on screen.
  void _followWorkspace() {
    if (!_showing || _chat.activeSlug == _pagesSlug) return;
    unawaited(openSection(_section));
  }

  /// Reads the text the server keeps of the document at [path], called [title], and shows it in
  /// place of the page.
  Future<void> viewText(String path, String title) async {
    _reading = (path: path, title: title);
    _pagesSlug = _chat.activeSlug;
    _text.reset();
    await _text.read(
      () => _api.document(path),
      failTitle: 'Could not read $title',
      kept: (_) => problems = const [],
      failed: (why) => problems = [why],
    );
  }

  /// The text the server keeps of the document at [path], or an [ApiException] when it cannot
  /// be read or the server left it out. The last [textsKept] read are kept, so reading one again
  /// asks the server nothing.
  Future<String> textOf(String path) async {
    if (_texts.remove(path) case final kept?) return _texts[path] = kept;
    final at = here;
    final text =
        (await _api.document(path)).text ??
        (throw const ApiException(noDocText));
    if (at.current) {
      _texts[path] = text;
      if (_texts.length > textsKept) _texts.remove(_texts.keys.first);
    }
    return text;
  }

  /// Puts the extracted text away, back to the page.
  void closeText() {
    if (_reading == null) return;
    _reading = null;
    _text.reset();
    notifyListeners();
  }

  /// Saves [draft] as the open section's prompt or settings. Returns whether it was saved.
  Future<bool> save(String draft) async {
    final slug = _pagesSlug;
    final detail = slug == null ? null : _details[slug];
    if (slug == null || detail == null) return false;
    final prompt = _section == FilesSection.instructions;
    final title = 'Could not save ${prompt ? 'PROMPT.md' : 'settings.json'}';
    final Map<String, Object?> fields;
    try {
      fields = prompt
          // An empty prompt is no prompt, so the default applies again.
          ? {'openAiPrompt': draft.trim().isEmpty ? null : draft}
          : parseSettings(
              draft,
              detail.settings ??
                  (throw const ApiException(
                    'The server did not send this workspace\'s settings, so they cannot be '
                    'saved.',
                  )),
            );
    } on ApiException catch (error) {
      problems = [Notice(title, error.message)];
      notifyListeners();
      return false;
    }
    if (fields.isEmpty) return true;
    return _change(title, () => _api.updateWorkspace(slug, fields), slug: slug);
  }

  /// Shows a failure that is not about one page, such as a file picker that would not open.
  void report(String title, String text) {
    problems = [...problems, Notice(title, text)];
    notifyListeners();
  }

  /// Runs [op], then reads workspace [slug] again. Says whether [op] worked; when the workspace
  /// could not be read again, the draft stays on screen with why.
  Future<bool> _change(
    String failTitle,
    Future<void> Function() op, {
    required String slug,
  }) {
    final at = here;
    return changeThenRead(
      failTitle,
      op,
      current: () => at.current,
      readAgain: (failed) async {
        final unread = await _readWorkspace(slug, keepDraft: failed != null);
        if (!at.current) return;
        problems = [?failed, ?unread];
        notifyListeners();
      },
    );
  }

  /// Reads workspace [slug] again and hands it to Sources. Returns why it could not, or null.
  /// A draft is dropped only when the read [keepDraft] is not.
  Future<Notice?> _readWorkspace(String slug, {bool keepDraft = false}) async {
    final at = here;
    try {
      final w = await _api.workspace(slug);
      if (!at.current) return null;
      _details[slug] = w;
      if (slug == _pagesSlug && !keepDraft) revision++;
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
}
