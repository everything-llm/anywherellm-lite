import 'package:flutter/foundation.dart';

/// What is open around the chat: the sidebar drawer, the Sources panel and the Settings dialog.
/// The sidebar is a drawer only below desktop width; Sources sits in the layout at wide widths
/// and is a drawer below that.
///
/// Sources keeps one open flag per layout: the panel in the layout starts open
/// ([sourcesPinned]), the drawer starts closed. [sourcesOpen] is the flag of the layout in use.
class ShellController extends ChangeNotifier {
  ShellController({this._sourcesPinned = true});

  bool _sideOpen = false;
  bool _sourcesPinned;
  bool _sourcesDrawer = false;
  bool _settingsOpen = false;

  /// Whether Sources sits in the layout, as the shell last laid it out.
  bool _inline = true;

  bool get sideOpen => _sideOpen;
  bool get sourcesOpen => _inline ? _sourcesPinned : _sourcesDrawer;
  bool get settingsOpen => _settingsOpen;

  /// Tells which layout Sources is in. The shell calls it as it lays out, so it does not notify.
  void fit({required bool sourcesInline}) => _inline = sourcesInline;

  void toggleSide() => _set(side: !_sideOpen);
  void closeSide() => _set(side: false);
  void toggleSources() => _setSources(!sourcesOpen);
  void openSources() => _setSources(true);
  void closeSources() => _setSources(false);
  void openSettings() => _set(settings: true, side: false);
  void closeSettings() => _set(settings: false);
  void closeDrawers() => _set(side: false, drawer: false);

  void _setSources(bool open) =>
      _inline ? _set(pinned: open) : _set(drawer: open);

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
