import 'package:flutter/widgets.dart';

import '../../core/chat.dart';
import '../settings/settings_pages.dart';
import 'chat_controller.dart';

/// What the main pane shows: the chat, or the server's data as files.
enum Pane { chats, files }

/// What the panel to the right of the chat shows: Sources, the chat's browser, or an app.
enum Beside { sources, browser, app }

/// What is open around the chat: the sidebar drawer, the Documents panel (Sources in the code),
/// the Settings dialog, the composer's Answer from menu and an answer's More menu, and which
/// [Pane] is on screen. The sidebar is a drawer only below desktop width; Sources sits in the
/// layout at wide widths and is a drawer below that.
///
/// The panel to the right of the chat shows Sources, the chat's browser or an app ([Beside]). It
/// keeps one open flag per layout: the panel in the layout starts open ([sourcesPinned]), the
/// drawer starts closed. [rightOpen] is the flag of the layout in use.
class ShellController extends ChangeNotifier {
  ShellController({this._sourcesPinned = true});

  bool _sideOpen = false;
  bool _menuOpen = false;

  /// The sidebar's search field.
  final searchFocus = FocusNode(debugLabel: 'Search chats');

  @override
  void dispose() {
    searchFocus.dispose();
    super.dispose();
  }

  bool _switcherOpen = false;

  /// Whether the Ctrl+K switcher is open over the window.
  bool get switcherOpen => _switcherOpen;

  /// Opens the switcher, or closes it when it is open. Settings keeps the window while it is
  /// open.
  void toggleSwitcher() {
    if (_settingsOpen && !_switcherOpen) return;
    _switcherOpen = !_switcherOpen;
    _menuOpen = false;
    _answerFromOpen = false;
    _answerMenu = null;
    notifyListeners();
  }

  void closeSwitcher() {
    if (!_switcherOpen) return;
    _switcherOpen = false;
    notifyListeners();
  }

  /// Whether the sidebar's workspace menu is open.
  bool get menuOpen => _menuOpen;

  void toggleMenu() {
    _menuOpen = !_menuOpen;
    notifyListeners();
  }

  void closeMenu() {
    if (!_menuOpen) return;
    _menuOpen = false;
    notifyListeners();
  }

  bool _answerFromOpen = false;

  /// Whether the composer's Answer from menu is open.
  bool get answerFromOpen => _answerFromOpen;

  void toggleAnswerFrom() {
    _answerFromOpen = !_answerFromOpen;
    notifyListeners();
  }

  void closeAnswerFrom() {
    if (!_answerFromOpen) return;
    _answerFromOpen = false;
    notifyListeners();
  }

  Turn? _answerMenu;

  /// The answer whose More menu is open, or null.
  Turn? get answerMenu => _answerMenu;

  /// Opens [answer]'s More menu, or closes it when it is open.
  void toggleAnswerMenu(Turn answer) {
    _answerMenu = identical(_answerMenu, answer) ? null : answer;
    notifyListeners();
  }

  /// Closes the More menu that is open, or only [answer]'s when it is given.
  void closeAnswerMenu([Turn? answer]) {
    if (_answerMenu == null ||
        (answer != null && !identical(_answerMenu, answer))) {
      return;
    }
    _answerMenu = null;
    notifyListeners();
  }

  bool _sourcesPinned;
  bool _sourcesDrawer = false;
  bool _settingsOpen = false;
  Pane _pane = Pane.chats;
  SettingsPage? _settingsPage;
  bool _allSettings = false;

  /// Whether Sources sits in the layout, as the shell last laid it out.
  bool _inline = true;

  /// What the panel to the right shows.
  Beside _beside = Beside.sources;

  /// Whether the panel was open before the browser took it, to be put back when it closes.
  bool _openBeforeBrowser = false;

  /// What the panel showed, and whether it was open, before an app took it, to be put back
  /// when the app closes.
  (Beside, bool) _beforeApp = (Beside.sources, false);

  AppCard? _app;

  /// The app the panel to the right shows, or showed last.
  AppCard? get app => _app;

  bool get sideOpen => _sideOpen;

  /// Whether the panel to the right is open. It is never open while Files is on screen.
  bool get rightOpen =>
      _pane == Pane.chats && (_inline ? _sourcesPinned : _sourcesDrawer);

  /// What the panel to the right shows, open or not.
  Beside get beside => _beside;

  bool get sourcesOpen => rightOpen && _beside == Beside.sources;
  bool get browserOpen => rightOpen && _beside == Beside.browser;
  bool get appOpen => rightOpen && _beside == Beside.app;
  bool get settingsOpen => _settingsOpen;

  /// The page Settings shows, or null for its list where the list and a page do not fit side by
  /// side; side by side, null is [SettingsPage.connection].
  SettingsPage? get settingsPage => _settingsPage;

  /// Whether Settings lists every page rather than the essentials alone.
  bool get allSettings => _allSettings;
  Pane get pane => _pane;

  /// Tells which layout Sources is in. The shell calls it as it lays out, so it does not notify.
  void fit({required bool sourcesInline}) => _inline = sourcesInline;

  void toggleSide() => _set(side: !_sideOpen);
  void closeSide() => _set(side: false);

  /// Shows Sources, or closes the panel when Sources already shows in it.
  void toggleSources() => _setRight(open: !sourcesOpen, beside: Beside.sources);
  void openSources() => _setRight(open: true, beside: Beside.sources);

  /// Closes the panel to the right, whatever it shows.
  void closeSources() => _setRight(open: false, beside: Beside.sources);

  /// Shows the chat's browser in the panel to the right, opening it.
  void showBrowser() {
    if (browserOpen) return;
    _openBeforeBrowser = sourcesOpen;
    _setRight(open: true, beside: Beside.browser);
  }

  /// Takes the browser out of the panel and puts back what was there: Sources, open or closed.
  void closeBrowser() {
    if (_beside == Beside.browser) {
      _setRight(open: _openBeforeBrowser, beside: Beside.sources);
    }
  }

  /// Shows [app] in the panel to the right, opening it; on a phone the shell draws it as a sheet
  /// over the chat instead.
  void showApp(AppCard app) {
    if (!appOpen) _beforeApp = (_beside, rightOpen);
    if (app != _app) {
      _app = app;
      notifyListeners();
    }
    _setRight(open: true, beside: Beside.app);
  }

  /// Takes the app out of the panel and puts back what was there, open or closed.
  void closeApp() {
    if (_beside != Beside.app) return;
    final (beside, open) = _beforeApp;
    _setRight(open: open, beside: beside);
  }

  /// Opens Settings on [page], or on its list.
  void openSettings([SettingsPage? page]) {
    _settingsPage = page;
    _allSettings |= !(page?.essential ?? true);
    _settingsOpen = true;
    _sideOpen = false;
    _menuOpen = false;
    _switcherOpen = false;
    _answerFromOpen = false;
    _answerMenu = null;
    notifyListeners();
  }

  void closeSettings() => _set(settings: false);

  void showSettingsPage(SettingsPage? page) {
    if (page == _settingsPage) return;
    _settingsPage = page;
    _allSettings |= !(page?.essential ?? true);
    notifyListeners();
  }

  /// Lists every page of Settings, or only the essentials, which leaves a page that is not one.
  void showAllSettings(bool all) {
    if (all == allSettings) return;
    _allSettings = all;
    if (!all && !(_settingsPage?.essential ?? true)) {
      _settingsPage = SettingsPage.connection;
    }
    notifyListeners();
  }

  void closeDrawers() {
    if (!_inline) _setRight(open: false, beside: Beside.sources);
    _set(side: false);
  }

  void showPane(Pane pane) {
    if (pane == _pane) return;
    _pane = pane;
    _menuOpen = false;
    _answerFromOpen = false;
    _answerMenu = null;
    notifyListeners();
  }

  void _setRight({required bool open, required Beside beside}) {
    if (beside != _beside) {
      _beside = beside;
      notifyListeners();
    }
    _inline ? _set(pinned: open) : _set(drawer: open);
  }

  void _set({bool? side, bool? pinned, bool? drawer, bool? settings}) {
    final next = (
      side ?? _sideOpen,
      pinned ?? _sourcesPinned,
      drawer ?? _sourcesDrawer,
      settings ?? _settingsOpen,
    );
    if (next == (_sideOpen, _sourcesPinned, _sourcesDrawer, _settingsOpen)) {
      return;
    }
    _sideOpen = next.$1;
    // The menu is the sidebar's: it goes with the drawer.
    if (!_sideOpen) _menuOpen = false;
    _sourcesPinned = next.$2;
    _sourcesDrawer = next.$3;
    _settingsOpen = next.$4;
    notifyListeners();
  }
}
