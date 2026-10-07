import 'package:flutter/foundation.dart';

import '../settings/settings_pages.dart';

/// What the main pane shows: the chat, or the server's data as files.
enum Pane { chats, files }

/// What is open around the chat: the sidebar drawer, the Sources panel and the Settings dialog,
/// and which [Pane] is on screen.
/// The sidebar is a drawer only below desktop width; Sources sits in the layout at wide widths
/// and is a drawer below that.
///
/// The panel to the right of the chat shows Sources or the chat's browser. It keeps one open
/// flag per layout: the panel in the layout starts open ([sourcesPinned]), the drawer starts
/// closed. [rightOpen] is the flag of the layout in use.
class ShellController extends ChangeNotifier {
  ShellController({this._sourcesPinned = true});

  bool _sideOpen = false;
  bool _sourcesPinned;
  bool _sourcesDrawer = false;
  bool _settingsOpen = false;
  Pane _pane = Pane.chats;
  SettingsPage? _settingsPage;
  bool _allSettings = false;

  /// Whether Sources sits in the layout, as the shell last laid it out.
  bool _inline = true;

  /// Whether the panel to the right shows the browser rather than Sources.
  bool _browser = false;

  /// Whether the panel was open before the browser took it, to be put back when it closes.
  bool _openBeforeBrowser = false;

  bool get sideOpen => _sideOpen;

  /// Whether the panel to the right is open. It is never open while Files is on screen.
  bool get rightOpen =>
      _pane == Pane.chats && (_inline ? _sourcesPinned : _sourcesDrawer);

  /// Whether the panel to the right shows the browser, open or not.
  bool get rightShowsBrowser => _browser;

  bool get sourcesOpen => rightOpen && !_browser;
  bool get browserOpen => rightOpen && _browser;
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
  void toggleSources() => _setRight(open: !sourcesOpen, browser: false);
  void openSources() => _setRight(open: true, browser: false);

  /// Closes the panel to the right, whatever it shows.
  void closeSources() => _setRight(open: false, browser: false);

  /// Shows the chat's browser in the panel to the right, opening it.
  void showBrowser() {
    if (browserOpen) return;
    _openBeforeBrowser = sourcesOpen;
    _setRight(open: true, browser: true);
  }

  /// Takes the browser out of the panel and puts back what was there: Sources, open or closed.
  void closeBrowser() {
    if (_browser) _setRight(open: _openBeforeBrowser, browser: false);
  }

  /// Opens Settings on [page], or on its list.
  void openSettings([SettingsPage? page]) {
    _settingsPage = page;
    _allSettings |= !(page?.essential ?? true);
    _settingsOpen = true;
    _sideOpen = false;
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
    if (!_inline) _setRight(open: false, browser: false);
    _set(side: false);
  }

  void showPane(Pane pane) {
    if (pane == _pane) return;
    _pane = pane;
    notifyListeners();
  }

  void _setRight({required bool open, required bool browser}) {
    if (browser != _browser) {
      _browser = browser;
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
    _sourcesPinned = next.$2;
    _sourcesDrawer = next.$3;
    _settingsOpen = next.$4;
    notifyListeners();
  }
}
