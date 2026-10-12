import 'package:flutter/foundation.dart';

import '../../core/apps.dart';
import '../../core/files.dart';
import '../../core/gallery.dart';
import '../../core/server_models.dart';
import '../settings/settings_pages.dart';
import '../share/shared_item.dart';
import 'chat_controller.dart';

/// What the main pane shows: the chat, or the open workspace's pages.
enum Pane { chats, files }

/// A tab of the bar at the foot of the home: the open workspace's chats, its apps where the
/// apps server is there, or Settings' list.
enum HomeTab { chats, apps, settings }

/// A page of an app's data, over the app shown full screen: its folder, one of its files,
/// its log, or its git history.
sealed class AppPage {
  const AppPage();
}

/// The app's folder: its files and its git history.
class AppFolder extends AppPage {
  const AppFolder();
}

/// One file of the app's folder, at [path], such as `app.json`.
class AppFileOf extends AppPage {
  const AppFileOf(this.path);

  final String path;
}

/// The app's `log.jsonl`, read as its history.
class AppLog extends AppPage {
  const AppLog();
}

/// The commits of the app's folder.
class AppGit extends AppPage {
  const AppGit();
}

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

/// A phone's sheet about the open workspace: a new workspace's name, the open one's new name,
/// or whether to delete it.
enum WorkspaceSheet { create, rename, delete }

/// A popup over the window, at most one open at a time: the workspace menu, the composer's Answer
/// from sheet, the Attach sheet, or the Memory page's choice of workspace. An answer's More sheet
/// is keyed by its [Turn] instead.
enum Popup { workspaces, answerFrom, attach, memoryWorkspace }

/// What is open over the home and its two tabs: the chat, full screen over them, the sheet over
/// the chat ([Beside]: the Documents panel, Sources in the code, or an answer's passages or
/// sources), Settings and the page of it shown, the [popup] open, and which [Pane] is on screen.
class ShellController extends ChangeNotifier {
  ShellController();

  bool _chatOpen = false;

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

  HomeTab _homeTab = HomeTab.chats;
  AppRef? _app;
  final List<AppPage> _appPages = [];

  /// The app shown full screen, over the home and the chat, or null.
  AppRef? get app => _app;

  /// The pages of the app's data open over it, the top one last.
  List<AppPage> get appPages => List.unmodifiable(_appPages);

  /// Shows [ref]'s working page full screen, or with [data] its folder over it.
  void openApp(AppRef ref, {bool data = false}) {
    _app = ref;
    _appPages
      ..clear()
      ..addAll([if (data) const AppFolder()]);
    _settingsOpen = false;
    _rightOpen = false;
    _popup.value = null;
    notifyListeners();
  }

  /// Opens [page] of the shown app's data over what shows.
  void showAppPage(AppPage page) {
    if (_app == null) return;
    _appPages.add(page);
    _popup.value = null;
    notifyListeners();
  }

  /// Steps back from the top page of the app's data, or closes the app when none is open.
  void appBack() {
    if (_appPages.isEmpty) return closeApp();
    _appPages.removeLast();
    notifyListeners();
  }

  void closeApp() {
    if (_app == null) return;
    _app = null;
    _appPages.clear();
    _popup.value = null;
    notifyListeners();
  }

  bool _rightOpen = false;
  FilesSection? _workspacePage;
  bool _scanning = false;
  bool _upcomingOpen = false;

  /// Whether the page of the server's scheduled jobs shows over the Chats tab, from its
  /// Upcoming card.
  bool get upcomingOpen => _upcomingOpen;

  /// Shows the Upcoming page over the Chats tab, closing the popup open.
  void openUpcoming() {
    if (_upcomingOpen) return;
    _upcomingOpen = true;
    _popup.value = null;
    notifyListeners();
  }

  void closeUpcoming() {
    if (!_upcomingOpen) return;
    _upcomingOpen = false;
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

  /// Whether Settings was opened on its page from elsewhere, not from its list, so that Back
  /// from a page with no parent gives back what was under it rather than the list.
  bool _settingsDirect = false;

  /// What the sheet over the chat shows.
  Beside _beside = Beside.sources;

  /// What the panel showed before passages or sources took it, to be put back when that closes:
  /// what it took over from, if not Sources, and whether Sources was open before either did.
  ({Beside? under, bool sources}) _before = (under: null, sources: false);

  Citation? _passages;

  /// The citation whose passages the sheet over the chat shows, or showed last.
  Citation? get passages => _passages;

  /// Whether the chat shows, full screen over the home.
  bool get chatOpen => _chatOpen;

  /// The tab the home shows: Settings while Settings is open, else Chats or Apps.
  HomeTab get tab => _settingsOpen ? HomeTab.settings : _homeTab;

  /// Whether the home shows, with the bar of its tabs: the Chats tab with nothing over it, or
  /// Settings' list.
  bool get atHome => _settingsOpen
      ? _settingsPage == null
      : !_chatOpen && _pane == Pane.chats && !_upcomingOpen && _app == null;

  /// Whether the sheet over the chat, or over the workspace's pages, is open.
  bool get rightOpen => _rightOpen;

  /// What the sheet over the chat shows, open or not.
  Beside get beside => _beside;

  bool get sourcesOpen => rightOpen && _beside == Beside.sources;
  bool get passagesOpen => rightOpen && _beside == Beside.passages;
  bool get citedOpen => rightOpen && _beside == Beside.cited;
  bool get settingsOpen => _settingsOpen;

  /// The page Settings shows, or null for its list.
  SettingsPage? get settingsPage => _settingsPage;

  Pane get pane => _pane;

  /// Shows the chat full screen over the home, closing Settings, the workspace's pages and a
  /// page over the Chats tab.
  void openChat() {
    if (_chatOpen &&
        !_settingsOpen &&
        _pane == Pane.chats &&
        !_upcomingOpen &&
        _app == null) {
      return;
    }
    _chatOpen = true;
    _settingsOpen = false;
    _scanning = false;
    _app = null;
    _appPages.clear();
    _sourcesUnder = null;
    _pane = Pane.chats;
    _workspacePage = null;
    _upcomingOpen = false;
    notifyListeners();
  }

  /// Takes the chat off the screen, back to the Chats tab. It stays built, so a draft and a
  /// running answer survive.
  void closeChat() {
    if (!_chatOpen) return;
    _chatOpen = false;
    _rightOpen = false;
    closePopup();
    notifyListeners();
  }

  /// Shows [tab] with nothing over it.
  void showTab(HomeTab tab) {
    _chatOpen = false;
    _rightOpen = false;
    _sourcesUnder = null;
    _pane = Pane.chats;
    _workspacePage = null;
    _upcomingOpen = false;
    _scanning = false;
    _settingsOpen = tab == HomeTab.settings;
    if (tab != HomeTab.settings) _homeTab = tab;
    _app = null;
    _appPages.clear();
    _settingsPage = null;
    _settingsDirect = false;
    _popup.value = null;
    notifyListeners();
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

  /// Opens Settings on [page], over what shows, so that Back from it gives that back; or on its
  /// list, the Settings tab, in place of whatever showed.
  void openSettings([SettingsPage? page]) {
    if (page == null) return showTab(HomeTab.settings);
    _settingsDirect = !_settingsOpen || _settingsDirect;
    _settingsPage = page;
    _systemShown = _systemTop;
    _settingsOpen = true;
    _popup.value = null;
    notifyListeners();
  }

  void closeSettings() {
    _scanning = false;
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
    _systemShown = _systemTop;
    notifyListeners();
  }

  static const _systemTop = (path: '', folder: true);
  ({String path, bool folder}) _systemShown = _systemTop;

  /// What the System files page shows: a folder or a file by its path, `""` the top.
  ({String path, bool folder}) get systemShown => _systemShown;

  /// Shows the System files folder or file at [path]; Back goes to the folder that holds it.
  void showSystemPath(String path, {required bool folder}) {
    _systemShown = (path: path, folder: folder);
    notifyListeners();
  }

  /// Goes back from the Settings page shown to the page it is reached from: the folder above in
  /// System files, the Server page, the list, or what showed under Settings when it opened on the page. From the list,
  /// Settings closes, back to the Chats tab.
  void settingsBack() {
    final page = _settingsPage;
    if (page == SettingsPage.systemFiles && _systemShown.path.isNotEmpty) {
      final path = _systemShown.path;
      showSystemPath(
        path.substring(0, path.lastIndexOf('/').clamp(0, path.length)),
        folder: true,
      );
    } else if (page == null) {
      closeSettings();
    } else if (page.parent == null && _settingsDirect) {
      closeSettings();
    } else {
      showSettingsPage(page.parent);
    }
  }

  void showPane(Pane pane) {
    if (pane == _pane) return;
    _pane = pane;
    _workspacePage = null;
    _rightOpen = false;
    _sourcesUnder = null;
    closePopup();
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
    closePopup();
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
