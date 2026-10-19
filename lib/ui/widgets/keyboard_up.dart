import 'package:flutter/widgets.dart';

/// Whether the on-screen keyboard is up. The shell takes the keyboard's inset out of the media
/// below it ([KeyboardUp] is how a page still learns of it), so a page that lays itself out
/// differently with the keyboard up, as the first run does, reads this.
class KeyboardUp extends InheritedWidget {
  const KeyboardUp({super.key, required this.up, required super.child});

  final bool up;

  /// Whether the keyboard is up above [context], or the media's own inset where there is no
  /// [KeyboardUp], as in a test that builds a widget alone.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KeyboardUp>()?.up ??
      MediaQuery.viewInsetsOf(context).bottom > 0;

  @override
  bool updateShouldNotify(KeyboardUp old) => up != old.up;
}
