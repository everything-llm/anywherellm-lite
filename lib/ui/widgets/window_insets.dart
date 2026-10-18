import 'package:flutter/widgets.dart';

/// The system bars' insets of the whole window, as they are above any page's [SafeArea]. A
/// scrim, a sheet or the shelf reaches the window's edges and keeps its words clear of the bars
/// by these; a page uses a [SafeArea]. An overlay is built where it was opened, inside a page's
/// [SafeArea], whose padding it would read as none, so it reads these. Put it above every
/// page; it reads the media itself, so what holds it does not rebuild when the bars change.
class WindowInsets extends StatelessWidget {
  const WindowInsets({super.key, required this.child});

  final Widget child;

  /// The insets above [context], or the media's own where there is no [WindowInsets], as in a
  /// test that builds a widget alone.
  static EdgeInsets of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Insets>()?.insets ??
      MediaQuery.paddingOf(context);

  @override
  Widget build(BuildContext context) =>
      _Insets(insets: MediaQuery.paddingOf(context), child: child);
}

class _Insets extends InheritedWidget {
  const _Insets({required this.insets, required super.child});

  final EdgeInsets insets;

  @override
  bool updateShouldNotify(_Insets old) => insets != old.insets;
}
