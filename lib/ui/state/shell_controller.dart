import 'package:flutter/foundation.dart';

import '../../core/files.dart';
import '../../core/gallery.dart';
import '../../core/server_models.dart';
import '../../core/skill_pages.dart';
import '../settings/settings_pages.dart';
import '../share/shared_item.dart';
import 'turn.dart';

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

/// browser-lean's page for an agent's [tab], in its tall sheet over the chat.
class BrowserOpen {
  const BrowserOpen(this.tab);

  final Uri tab;
}

/// One of the suite's pages on the connected server at [url], such as an apps-lean app's page,
/// in a tall sheet over the chat, its address as it opens ([SkillPage.openedAt]).
class PageOpen {
  const PageOpen(this.url);

  final Uri url;
}

/// A walk-through over the whole window: How connecting works, over the Connection page and the
/// camera, or Add the toolkit, over Settings' list.
enum Guide { connect, toolkit }

/// A phone's sheet for one chat of the workspace on screen: its name, its pin and Delete, or
/// with [deleting] the question whether to delete it.
class ChatSheetFor {
  const ChatSheetFor(this.thread, {this.deleting = false});

  final Thread thread;
  final bool deleting;
}

/// A phone's sheet about the open workspace: a new workspace's name, the open one's new name,
/// or whether to delete it.
enum WorkspaceSheet { create, rename, delete }

/// A popup over the window, at most one open at a time: the workspace menu, the composer's Answer
/// from sheet, the Attach sheet, the Memory page's choice of workspace, or a question before
/// forgetting the server or removing a document. An answer's More sheet
/// is keyed by its [Turn] instead.
enum Popup {
  workspaces,
  answerFrom,
  attach,
  memoryWorkspace,

  /// Forget this server?, on the Connection page.
  forgetServer,

  /// Remove from workspace?, under a document's text.
  removeDoc,
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
    super.dispose();
  }

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

  /// Shows [tab], browser-lean's page for an agent's tab, in its sheet over the chat, closing
  /// any other popup.
  void openBrowser(Uri tab) => _popup.value = BrowserOpen(tab);

  /// Closes the agent's browser, when it is open.
  void closeBrowser() {
    if (_popup.value is BrowserOpen) _popup.value = null;
  }

  /// Shows [url], one of the suite's pages on the connected server, in its sheet over the chat,
  /// closing any other popup.
  void openPage(Uri url) => _popup.value = PageOpen(url);

  /// Closes the page's sheet, when it is open.
  void closePage() {
    if (_popup.value is PageOpen) _popup.value = null;
  }

  /// Opens [thread]'s sheet, closing any other popup.
  void openChatSheet(Thread thread, {bool deleting = false}) =>
      _popup.value = ChatSheetFor(thread, deleting: deleting);

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
  /// A document's text forgets what it was opened over.
  void _reset() {
    _coverChat();
    _sourcesUnder = null;
    _pane = Pane.chats;
    _workspacePage = null;
    _scanning = false;
    _guide = null;
    _rightOpen = false;
    _settingsOpen = false;
    _settingsPage = null;
    _settingsDirect = false;
  }

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
  /// closes, back to the chat.
  void settingsBack() {
    final page = _settingsPage;
    if (page == null) {
      closeSettings();
    } else if (page.parent == null && _settingsDirect) {
      closeSettings();
    } else {
      showSettingsPage(page.parent);
    }
  }

  void showPane(Pane pane) {
    if (pane == _pane) return;
    _coverChat();
    _pane = pane;
    _workspacePage = null;
    _rightOpen = false;
    _sourcesUnder = null;
    notifyListeners();
  }

  /// What showed under the Documents sheet when a document's text was opened from it, or null
  /// when the text was opened otherwise.
  Pane? _sourcesUnder;

  /// Shows a document's text, picked in the Documents sheet, in the workspace's pages in place
  /// of the sheet, which [textClosed] gives back.
  void showDocText() {
    _sourcesUnder = _pane;
    _rightOpen = false;
    _beside = Beside.sources;
    _pane = Pane.files;
    _workspacePage = null;
    _popup.value = null;
    notifyListeners();
  }

  /// After a document's text closes: when it was opened from the Documents sheet, the sheet
  /// over what showed under it.
  void textClosed() {
    final under = _sourcesUnder;
    if (under == null) return;
    _sourcesUnder = null;
    _pane = under;
    _beside = Beside.sources;
    _rightOpen = true;
    notifyListeners();
  }

  void _setRight({required bool open, required Beside beside}) {
    if (beside == _beside && open == _rightOpen) return;
    _beside = beside;
    _rightOpen = open;
    notifyListeners();
  }
}
