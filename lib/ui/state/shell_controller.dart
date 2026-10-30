import 'package:flutter/foundation.dart';

import '../../core/files.dart';
import '../../core/gallery.dart';
import '../../core/server_models.dart';
import '../../core/sources.dart';
import '../settings/settings_pages.dart';
import '../share/shared_item.dart';
import 'turn.dart';

/// What the main pane shows: the chat, the open workspace's pages, or, on a wide window, its
/// Documents as a list beside what it opens.
enum Pane { chats, files, documents }

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

/// What the Sources panel beside the chat follows on a wide window: [turn]'s sources, with the
/// one numbered [source] from 0 chosen, or none.
class AsideChoice {
  const AsideChoice(this.turn, [this.source]);

  final Turn turn;
  final int? source;
}

/// A walk-through over the whole window: How connecting works, over the Connection page and the
/// camera.
enum Guide { connect }

/// A phone's sheet for one chat of the workspace on screen: its name, its pin and Delete.
class ChatSheetFor {
  const ChatSheetFor(this.thread);

  final Thread thread;
}

/// A phone's sheet about the open workspace: a new workspace's name, the open one's new name,
/// or whether to delete it.
enum WorkspaceSheet { create, rename, delete }

/// A popup over the window, at most one open at a time: the workspace menu and its Reorder
/// workspaces, the composer's Answer from sheet, the Attach sheet, the question before forgetting
/// the server, Who uses this app?, or a document's Move to folder sheet or question before
/// deleting it. An answer's This answer sheet is keyed by its [Turn] instead.
enum Popup {
  workspaces,

  /// Reorder workspaces, opened from the workspace menu's Reorder.
  reorderWorkspaces,
  answerFrom,
  attach,

  /// Forget this server?, on the Connection page.
  forgetServer,

  /// Who uses this app?, on the Connection page of a server with several users.
  whoUses,
  /// Move to folder, over the [ShellController.document] whose details show.
  moveDocument,

  /// Delete from server, over the [ShellController.document] whose details show.
  deleteDocument,
}

/// What is open over the chat, which is the base screen: the chats as a shelf,
/// the sheet over the chat ([Beside]: the Documents panel, Sources in the code, or an answer's
/// passages or sources), Settings and the page of it shown, the [popup] open, and which [Pane] is on screen.
class ShellController extends ChangeNotifier {
  ShellController();

  final _popup = ValueNotifier<Object?>(null);

  @override
  void dispose() {
    _popup.dispose();
    aside.dispose();
    super.dispose();
  }

  /// The answer, and the source of it, that the Sources panel beside the chat follows once a
  /// chip picked them; null, or an answer no longer on screen, follows the chat's latest answer
  /// with sources. It notifies apart from the shell.
  final aside = ValueNotifier<AsideChoice?>(null);

  /// The popup open: a [Popup], or the [Turn] whose More menu is open, or null. It notifies
  /// apart from the shell, so opening or closing one rebuilds only what listens to it.
  ValueListenable<Object?> get popup => _popup;

  /// Whether the workspace menu is open.
  bool get menuOpen => _popup.value == Popup.workspaces;

  /// Whether the composer's Answer from menu is open.
  bool get answerFromOpen => _popup.value == Popup.answerFrom;

  /// Opens the page of [pictures] at [index], over the window.
  void openGallery(List<Picture> pictures, int index, {required String chat}) =>
      _popup.value = GalleryOpen(pictures, index, chat: chat);

  /// Opens [thread]'s sheet, closing any other popup.
  void openChatSheet(Thread thread) => _popup.value = ChatSheetFor(thread);

  /// Opens the popup [key], closing any other, or closes it when it is open.
  void togglePopup(Object key) =>
      _popup.value = identical(_popup.value, key) ? null : key;

  /// Closes the popup open, or only [key] when it is given.
  void closePopup([Object? key]) {
    if (key == null || identical(_popup.value, key)) _popup.value = null;
  }

  bool _rightOpen = false;
  FilesSection? _workspacePage;
  String? _document;

  /// The document whose details show, by its [SourceFile.storedName], which moving it to
  /// another folder keeps, or null: over the Documents sheet as a page of its own, or in the
  /// Documents pane, beside its list on a wide window.
  String? get document => _document;

  /// Shows the details of the document stored as [name], closing any popup.
  void openDocument(String name) {
    _popup.value = null;
    if (name == _document) return;
    _document = name;
    notifyListeners();
  }

  /// Puts the document's details away, back to Documents.
  void closeDocument() {
    if (_document == null) return;
    _document = null;
    notifyListeners();
  }

  bool _scanning = false;
  Guide? _guide;
  int _guideStep = 0;

  SharedItem? _shared;

  /// What the shell offers over the window, or null: what another app shared, to add or ask
  /// about, or a pairing code another app opened or the camera read, to connect with.
  SharedItem? get shared => _shared;

  /// Offers [item], shared from another app or scanned, over whatever shows.
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

  String? _pairing;

  /// Opens Settings' Connection page to connect with [code], a pairing code, as if it had been
  /// scanned there.
  void pairWith(String code) {
    _pairing = code;
    openSettings(SettingsPage.connection);
  }

  /// The pairing code [pairWith] left for the Connection page, once; null when none waits.
  String? takePairing() {
    final code = _pairing;
    _pairing = null;
    return code;
  }

  void setScanning(bool on) {
    if (on == _scanning) return;
    _scanning = on;
    notifyListeners();
  }

  /// The walk-through shown over the window, or null. Esc and Back close it before the camera.
  Guide? get guide => _guide;

  /// Whether a walk-through shows over the window.
  bool get guiding => _guide != null;

  /// The screen the walk-through opened on, counted from 0.
  int get guideStep => _guideStep;

  /// Shows [guide] over the window, opening on screen [step], or none.
  void showGuide(Guide? guide, {int step = 0}) {
    if (guide == _guide) return;
    _guide = guide;
    _guideStep = step;
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

  /// Whether Settings was opened on its page from elsewhere, not from its list, so that Back
  /// from a page with no parent gives back what was under it rather than the list.
  bool _settingsDirect = false;

  /// What the sheet over the chat shows.
  Beside _beside = Beside.sources;

  /// What the panel showed before passages or sources took it, bottom first, put back as each
  /// closes: Sources when it was open before either did, then what the one showing took over
  /// from, if not Sources.
  final List<Beside> _under = [];

  Citation? _passages;

  /// The citation whose passages the sheet over the chat shows, or showed last.
  Citation? get passages => _passages;

  /// Whether the sheet over the chat, or over the workspace's pages, is open.
  bool get rightOpen => _rightOpen;

  /// What the sheet over the chat shows, open or not.
  Beside get beside => _beside;

  bool get passagesOpen => rightOpen && _beside == Beside.passages;
  bool get citedOpen => rightOpen && _beside == Beside.cited;
  bool get settingsOpen => _settingsOpen;

  /// The page Settings shows, or null for its list.
  SettingsPage? get settingsPage => _settingsPage;

  Pane get pane => _pane;

  bool _shelfOpen = false;

  /// Whether the chats show as a shelf from the left over the chat, which is the only place
  /// they show.
  bool get shelfOpen => _shelfOpen;

  /// Slides the chats in from the left over the chat.
  void openShelf() {
    if (_shelfOpen) return;
    _shelfOpen = true;
    _popup.value = null;
    notifyListeners();
  }

  void closeShelf() {
    if (!_shelfOpen) return;
    _shelfOpen = false;
    notifyListeners();
  }

  /// What every cover over the chat does first: puts the shelf away, which would stay open
  /// under it, and closes the popup open.
  void _coverChat() {
    _shelfOpen = false;
    _popup.value = null;
  }

  /// Shows the chat with nothing over it: the shelf, the sheet, the popup, Settings, the
  /// workspace's pages are closed.
  void openChat() {
    _reset();
    notifyListeners();
  }

  /// Closes everything over the chat, without telling listeners: the shelf, the sheet, the popup,
  /// the workspace's pages, the scanner, the walk-through and Settings.
  void _reset() {
    _coverChat();
    _pane = Pane.chats;
    _workspacePage = null;
    _scanning = false;
    _guide = null;
    _rightOpen = false;
    _document = null;
    _settingsOpen = false;
    _settingsPage = null;
    _settingsDirect = false;
    _overPages = false;
  }

  bool _overPages = false;

  /// Whether the Documents pane opened over the workspace's pages, which [closePane] gives back.
  bool get overPages => _overPages;

  /// Opens the open workspace's Documents: the sheet over what shows, or [asPane], as a wide
  /// window does, the Documents pane in place of what shows.
  void openSources({bool asPane = false}) {
    if (!asPane) return _setRight(open: true, beside: Beside.sources);
    openPane(Pane.documents, overPages: _pane == Pane.files);
  }

  /// Leaves Documents as a pane for the workspace's pages when Documents opened over
  /// them, or the chat.
  void closePane() =>
      showPane(_pane == Pane.documents && _overPages ? Pane.files : Pane.chats);

  /// Closes the sheet over the chat, whatever it shows, and a document's details over it.
  void closeSources() {
    _document = null;
    _setRight(open: false, beside: Beside.sources);
  }

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
    if (!rightOpen || _beside == Beside.sources) {
      _under.clear();
    } else {
      // What the one showing took over from is let go: only Sources stays under it.
      _under.removeWhere((shown) => shown != Beside.sources);
    }
    if (rightOpen) _under.add(_beside);
    _setRight(open: true, beside: next);
  }

  /// Takes [shown] out of the panel, if it is there, and puts back what it took over from.
  void _giveBack(Beside shown) {
    if (_beside != shown) return;
    final under = _under.isEmpty ? null : _under.removeLast();
    _setRight(open: under != null, beside: under ?? Beside.sources);
  }

  /// Opens Settings on [page], over what shows, so that Back from it gives that back; or on its
  /// list, over the chat with nothing else open, as the shelf's Settings row does.
  void openSettings([SettingsPage? page]) {
    if (page == null) {
      _reset();
      _settingsOpen = true;
      return notifyListeners();
    }
    _settingsDirect = !_settingsOpen || _settingsDirect;
    _coverChat();
    _settingsPage = page;
    _settingsOpen = true;
    notifyListeners();
  }

  void closeSettings() {
    _scanning = false;
    _guide = null;
    if (!_settingsOpen) return;
    _settingsOpen = false;
    _settingsDirect = false;
    notifyListeners();
  }

  /// Shows Settings' [page], or its list. A page opened from the list goes back to it.
  void showSettingsPage(SettingsPage? page) {
    if (page == _settingsPage) return;
    if (_settingsPage == null) _settingsDirect = false;
    _settingsPage = page;
    notifyListeners();
  }

  /// Goes back from the Settings page shown to the page it is reached from: the Server page, the
  /// list, or what showed under Settings when it opened on the page. From the list, Settings
  /// closes, back to the chat, and so it does from a page with no parent when Settings shows its
  /// list beside the page ([split]), as on a wide window.
  void settingsBack({bool split = false}) {
    final page = _settingsPage;
    if (page == null) {
      closeSettings();
    } else if (page.parent == null && (_settingsDirect || split)) {
      closeSettings();
    } else {
      showSettingsPage(page.parent);
    }
  }

  /// Shows [pane] with nothing over it, as the sidebar's rows do; the Documents pane goes back
  /// to the workspace's pages when it opens [overPages].
  void openPane(Pane pane, {bool overPages = false}) {
    _reset();
    _pane = pane;
    _overPages = overPages;
    notifyListeners();
  }

  void showPane(Pane pane) {
    if (pane == _pane) return;
    _coverChat();
    _pane = pane;
    _workspacePage = null;
    _rightOpen = false;
    _document = null;
    notifyListeners();
  }

  void _setRight({required bool open, required Beside beside}) {
    if (beside == _beside && open == _rightOpen) return;
    _beside = beside;
    _rightOpen = open;
    notifyListeners();
  }
}
