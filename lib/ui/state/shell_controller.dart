import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/chat.dart';
import '../../core/files.dart';
import '../settings/settings_pages.dart';
import '../share/shared_item.dart';
import 'chat_controller.dart';

/// What the main pane shows: the chat, or the server's data as files.
enum Pane { chats, files }

/// What the panel to the right of the chat shows: Sources, the chat's browser, or an app.
enum Beside { sources, browser, app }

/// A popup over the window or a part of it, at most one open at a time: the sidebar's workspace
/// menu, the Ctrl+K switcher, or the composer's Answer from menu. An answer's More menu is
/// keyed by its [Turn] instead.
enum Popup { workspaces, switcher, answerFrom }

/// What is open around the chat: the sidebar drawer, the Documents panel (Sources in the code),
/// the Settings dialog, the [popup] open, and which [Pane] is on screen. The sidebar is a drawer
/// only below desktop width; Sources sits in the layout at wide widths and is a drawer below
/// that.
///
/// The panel to the right of the chat shows Sources, the chat's browser or an app ([Beside]). It
/// keeps one open flag per layout: the panel in the layout starts open ([sourcesPinned]), the
/// drawer starts closed. [rightOpen] is the flag of the layout in use.
class ShellController extends ChangeNotifier {
  ShellController({this._sourcesPinned = true});

  bool _sideOpen = false;

  /// The sidebar's search field.
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

  /// Whether the Ctrl+K switcher is open over the window.
  bool get switcherOpen => _popup.value == Popup.switcher;

  /// Whether the sidebar's workspace menu is open.
  bool get menuOpen => _popup.value == Popup.workspaces;

  /// Whether the composer's Answer from menu is open.
  bool get answerFromOpen => _popup.value == Popup.answerFrom;

  /// The answer whose More menu is open, or null.
  Turn? get answerMenu => switch (_popup.value) {
    final Turn turn => turn,
    _ => null,
  };

  /// Opens the popup [key], closing any other, or closes it when it is open.
  void togglePopup(Object key) =>
      _popup.value = identical(_popup.value, key) ? null : key;

  /// Closes the popup open, or only [key] when it is given.
  void closePopup([Object? key]) {
    if (key == null || identical(_popup.value, key)) _popup.value = null;
  }

  /// Opens the switcher, or closes it when it is open. Settings keeps the window while it is
  /// open.
  void toggleSwitcher() {
    if (_settingsOpen && !switcherOpen) return;
    togglePopup(Popup.switcher);
  }

  bool _sourcesPinned;
  bool _sourcesDrawer = false;
  FilesSection? _workspacePage;
  bool _scanning = false;
  bool _upcoming = false;

  /// Whether a phone's Upcoming page shows over the chat.
  bool get upcomingOpen => _upcoming;

  void openUpcoming() {
    if (_upcoming) return;
    _upcoming = true;
    _popup.value = null;
    notifyListeners();
  }

  void closeUpcoming() {
    if (!_upcoming) return;
    _upcoming = false;
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

  /// On a phone, where Files is the open workspace's pages: the page open, or null for the list
  /// of them.
  FilesSection? get workspacePage => _workspacePage;

  /// Opens one of the workspace's pages on a phone, or the list of them.
  void showWorkspacePage(FilesSection? page) {
    if (page == _workspacePage) return;
    _workspacePage = page;
    notifyListeners();
  }

  bool _settingsOpen = false;
  Pane _pane = Pane.chats;
  SettingsPage? _settingsPage;
  bool _allSettings = false;

  /// Whether Sources sits in the layout, as the shell last laid it out.
  bool _inline = true;

  /// What the panel to the right shows.
  Beside _beside = Beside.sources;

  /// What the panel showed before the browser or an app took it, to be put back when that
  /// closes: the browser or app it took over from, if one showed, and whether Sources was open
  /// before either did.
  ({Beside? under, bool sources}) _before = (under: null, sources: false);

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
  void showBrowser() => _take(Beside.browser);

  /// Takes the browser out of the panel and puts back what was there, open or closed.
  void closeBrowser() => _giveBack(Beside.browser);

  /// Shows [app] in the panel to the right, opening it; on a phone the shell draws it as a sheet
  /// over the chat instead.
  void showApp(AppCard app) {
    if (app != _app) {
      _app = app;
      notifyListeners();
    }
    _take(Beside.app);
  }

  /// Takes the app out of the panel and puts back what was there, open or closed.
  void closeApp() => _giveBack(Beside.app);

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
    _allSettings |= !(page?.essential ?? true);
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
    _allSettings |= !(page?.essential ?? true);
    notifyListeners();
  }

  /// Goes back from the Settings page shown: on a [phone] to the page it was opened from, the
  /// Server page or the list; elsewhere to the list. From the list, Settings closes.
  void settingsBack({required bool phone}) {
    final page = _settingsPage;
    if (page == null) {
      closeSettings();
    } else {
      showSettingsPage(phone ? page.phoneParent : null);
    }
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
    _workspacePage = null;
    closePopup();
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
    if (!_sideOpen) closePopup(Popup.workspaces);
    _sourcesPinned = next.$2;
    _sourcesDrawer = next.$3;
    _settingsOpen = next.$4;
    notifyListeners();
  }
}
