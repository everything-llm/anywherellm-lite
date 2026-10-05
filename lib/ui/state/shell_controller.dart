import 'package:flutter/foundation.dart';

/// Whether the sidebar drawer is open. The sidebar is a drawer only at tablet width; wider, it
/// sits in the layout.
class ShellController extends ChangeNotifier {
  bool _sideOpen = false;

  bool get sideOpen => _sideOpen;

  void toggle() => _set(!_sideOpen);

  void close() => _set(false);

  void _set(bool open) {
    if (open == _sideOpen) return;
    _sideOpen = open;
    notifyListeners();
  }
}
