import 'package:flutter/foundation.dart';

/// What is open around the chat: the sidebar drawer, the Sources panel and the Settings dialog.
/// The sidebar is a drawer only below desktop width; Sources sits in the layout at wide widths
/// and is a drawer below that.
class ShellController extends ChangeNotifier {
  ShellController({this._sourcesOpen = false});

  bool _sideOpen = false;
  bool _sourcesOpen;
  bool _settingsOpen = false;

  bool get sideOpen => _sideOpen;
  bool get sourcesOpen => _sourcesOpen;
  bool get settingsOpen => _settingsOpen;

  void toggleSide() => _set(side: !_sideOpen);
  void closeSide() => _set(side: false);
  void toggleSources() => _set(sources: !_sourcesOpen);
  void openSources() => _set(sources: true);
  void closeSources() => _set(sources: false);
  void openSettings() => _set(settings: true, side: false);
  void closeSettings() => _set(settings: false);
  void closeDrawers() => _set(side: false, sources: false);

  void _set({bool? side, bool? sources, bool? settings}) {
    final next = (
      side ?? _sideOpen,
      sources ?? _sourcesOpen,
      settings ?? _settingsOpen,
    );
    if (next == (_sideOpen, _sourcesOpen, _settingsOpen)) return;
    _sideOpen = next.$1;
    _sourcesOpen = next.$2;
    _settingsOpen = next.$3;
    notifyListeners();
  }
}
