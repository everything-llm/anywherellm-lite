import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/files.dart';
import '../../core/gallery.dart';
import '../../core/server_models.dart';
import '../settings/settings_pages.dart';
import '../share/shared_item.dart';
import 'chat_controller.dart';

/// What the main pane shows: the chat, or the open workspace's pages.
enum Pane { chats, files }

/// What the sheet over the chat shows: Sources, the passages an answer read from one
/// file, or all of an answer's sources ([cited]).
enum Beside { sources, passages, cited }

/// The page over the window that shows an answer's [pictures] one at a time, from [index], in
/// the chat named [chat].
class GalleryOpen {
  const GalleryOpen(this.pictures, this.index, {required this.chat});

  final List<Picture> pictures;
  final int index;
  final String chat;
}

/// A phone's sheet for one chat of the workspace on screen: its name, its pin and Delete, or
/// with [deleting] the question whether to delete it.
class ChatSheetFor {
  const ChatSheetFor(this.thread, {this.deleting = false});

  final Thread thread;
  final bool deleting;
}

/// A page a phone shows over the chat, from its drawer: the server's scheduled jobs.
enum PhonePage { upcoming }

/// A phone's sheet about the open workspace: a new workspace's name, the open one's new name,
/// or whether to delete it.
enum WorkspaceSheet { create, rename, delete }

/// A popup over the window, at most one open at a time: the workspace menu, the composer's Answer
/// from sheet, or the Attach sheet. An answer's More sheet is keyed by its [Turn] instead.
enum Popup { workspaces, answerFrom, attach }

/// What is open around the chat: the drawer, the sheet over the chat ([Beside]: the Documents
/// panel, Sources in the code, or an answer's passages or sources), Settings, the [popup] open,
/// and which [Pane] is on screen.
class ShellController extends ChangeNotifier {
  ShellController();

  bool _sideOpen = false;

  /// The drawer's search field.
  final searchFocus = FocusNode(debugLabel: 'Search chats');

  final _popup = ValueNotifier<Object?>(null);

  @override
  void dispose() {
    searchFocus.dispose();
    _popup.dispose();
    super.dispose();
  }

  /// The popup open: a [Popup], or the [Turn] whose More menu is open, or null. It notifies
  /// apart from the shell, so opening or closing one rebuilds only what listens to it.
  ValueListenable<Object?> get popup => _popup;

  /// Whether the workspace menu is open.
  bool get menuOpen => _popup.value == Popup.workspaces;

  /// Whether the composer's Answer from menu is open.
  bool get answerFromOpen => _popup.value == Popup.answerFrom;

  /// The answer whose More menu is open, or null.
  Turn? get answerMenu => switch (_popup.value) {
    final Turn turn => turn,
    _ => null,
  };

  /// The chat whose sheet is open, or null.
  ChatSheetFor? get chatSheet => switch (_popup.value) {
    final ChatSheetFor sheet => sheet,
    _ => null,
  };

  /// Opens the page of [pictures] at [index], over the window.
  void openGallery(List<Picture> pictures, int index, {required String chat}) =>
      _popup.value = GalleryOpen(pictures, index, chat: chat);

  /// Opens [thread]'s sheet, closing any other popup and the drawer.
  void openChatSheet(Thread thread, {bool deleting = false}) {
    _popup.value = ChatSheetFor(thread, deleting: deleting);
    closeSide();
  }

  /// Opens the popup [key], closing any other, or closes it when it is open.
  void togglePopup(Object key) =>
      _popup.value = identical(_popup.value, key) ? null : key;

  /// Closes the popup open, or only [key] when it is given.
  void closePopup([Object? key]) {
    if (key == null || identical(_popup.value, key)) _popup.value = null;
  }

  bool _rightOpen = false;
  FilesSection? _workspacePage;
  bool _scanning = false;
  PhonePage? _phonePage;

  /// The page a phone shows over the chat, or null: one at a time.
  PhonePage? get phonePage => _phonePage;

  /// Shows [page] over the chat in place of any other, closing the popup open.
  void openPhonePage(PhonePage page) {
    if (_phonePage == page) return;
    _phonePage = page;
    _popup.value = null;
    notifyListeners();
  }

  void closePhonePage() {
    if (_phonePage == null) return;
    _phonePage = null;
    notifyListeners();
  }

  SharedItem? _shared;

  /// What another app shared with AnywhereLLM, which the shell offers to add or ask about, or
  /// null.
  SharedItem? get shared => _shared;

  /// Offers [item], shared from another app, over whatever shows.
  void showShared(SharedItem item) {
    _shared = item;
    _popup.value = null;
    notifyListeners();
  }

  void closeShared() {
    if (_shared == null) return;
    _shared = null;
    notifyListeners();
  }

  /// Whether Settings is reading a pairing code with the camera, which Esc and Back stop first.
  bool get scanning => _scanning;

  void setScanning(bool on) {
    if (on == _scanning) return;
    _scanning = on;
    notifyListeners();
  }

  /// The workspace's page open while [Pane.files] shows, or null for the list of them.
  FilesSection? get workspacePage => _workspacePage;

  /// Opens one of the workspace's pages, or the list of them.
  void showWorkspacePage(FilesSection? page) {
    if (page == _workspacePage) return;
    _workspacePage = page;
    notifyListeners();
  }

  bool _settingsOpen = false;
  Pane _pane = Pane.chats;
  SettingsPage? _settingsPage;

  /// What the sheet over the chat shows.
  Beside _beside = Beside.sources;

  /// What the panel showed before passages or sources took it, to be put back when that closes:
  /// what it took over from, if not Sources, and whether Sources was open before either did.
  ({Beside? under, bool sources}) _before = (under: null, sources: false);

  Citation? _passages;

  /// The citation whose passages the sheet over the chat shows, or showed last.
  Citation? get passages => _passages;

  bool get sideOpen => _sideOpen;

  /// Whether the sheet over the chat is open. It is never open while Files is on screen.
  bool get rightOpen => _pane == Pane.chats && _rightOpen;

  /// What the sheet over the chat shows, open or not.
  Beside get beside => _beside;

  bool get sourcesOpen => rightOpen && _beside == Beside.sources;
  bool get passagesOpen => rightOpen && _beside == Beside.passages;
  bool get citedOpen => rightOpen && _beside == Beside.cited;
  bool get settingsOpen => _settingsOpen;

  /// The page Settings shows, or null for its list.
  SettingsPage? get settingsPage => _settingsPage;

  Pane get pane => _pane;

  void toggleSide() => _set(side: !_sideOpen);
  void closeSide() => _set(side: false);

  void openSources() => _setRight(open: true, beside: Beside.sources);

  /// Closes the sheet over the chat, whatever it shows.
  void closeSources() => _setRight(open: false, beside: Beside.sources);

  /// Shows the passages an answer read from [citation]'s file in the sheet over the chat,
  /// opening it, or closes it when it already shows them.
  void togglePassages(Citation citation) {
    if (passagesOpen && _passages == citation) return closePassages();
    if (citation != _passages) {
      _passages = citation;
      notifyListeners();
    }
    _take(Beside.passages);
  }

  /// Takes the passages out of the panel and puts back what was there, open or closed.
  void closePassages() => _giveBack(Beside.passages);

  List<Citation>? _cited;

  /// The sources of the answer the sheet over the chat lists, or listed last.
  List<Citation>? get cited => _cited;

  /// Lists all of an answer's [citations] in the sheet over the chat, opening it, or closes it
  /// when it already lists them.
  void toggleCited(List<Citation> citations) {
    if (citedOpen && identical(_cited, citations)) return closeCited();
    if (!identical(citations, _cited)) {
      _cited = citations;
      notifyListeners();
    }
    _take(Beside.cited);
  }

  /// Takes an answer's sources out of the panel and puts back what was there, open or closed.
  void closeCited() => _giveBack(Beside.cited);

  /// Opens the panel on [next], remembering what it showed.
  void _take(Beside next) {
    if (rightOpen && _beside == next) return;
    _before = !rightOpen
        ? (under: null, sources: false)
        : _beside == Beside.sources
        ? (under: null, sources: true)
        : (under: _beside, sources: _before.sources);
    _setRight(open: true, beside: next);
  }

  /// Takes [shown] out of the panel, if it is there, and puts back what it took over from.
  void _giveBack(Beside shown) {
    if (_beside != shown) return;
    final (:under, :sources) = _before;
    _before = (under: null, sources: sources);
    under == null
        ? _setRight(open: sources, beside: Beside.sources)
        : _setRight(open: true, beside: under);
  }

  /// Opens Settings on [page], or on its list.
  void openSettings([SettingsPage? page]) {
    _settingsPage = page;
    _settingsOpen = true;
    _sideOpen = false;
    _popup.value = null;
    notifyListeners();
  }

  void closeSettings() {
    _scanning = false;
    _set(settings: false);
  }

  void showSettingsPage(SettingsPage? page) {
    if (page == _settingsPage) return;
    _settingsPage = page;
    notifyListeners();
  }

  /// Goes back from the Settings page shown to the page it is reached from, the Server page or
  /// the list. From the list, Settings closes.
  void settingsBack() {
    final page = _settingsPage;
    if (page == null) {
      closeSettings();
    } else {
      showSettingsPage(page.parent);
    }
  }

  void showPane(Pane pane) {
    if (pane == _pane) return;
    _pane = pane;
    _workspacePage = null;
    closePopup();
    notifyListeners();
  }

  void _setRight({required bool open, required Beside beside}) {
    if (beside != _beside) {
      _beside = beside;
      notifyListeners();
    }
    _set(right: open);
  }

  void _set({bool? side, bool? right, bool? settings}) {
    final next = (
      side ?? _sideOpen,
      right ?? _rightOpen,
      settings ?? _settingsOpen,
    );
    if (next == (_sideOpen, _rightOpen, _settingsOpen)) return;
    _sideOpen = next.$1;
    // The menu is the drawer's: it goes with the drawer.
    if (!_sideOpen) closePopup(Popup.workspaces);
    _rightOpen = next.$2;
    _settingsOpen = next.$3;
    notifyListeners();
  }
}
