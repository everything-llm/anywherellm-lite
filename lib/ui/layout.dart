import 'package:flutter/widgets.dart';

/// Widths at which the shell changes.
enum ScreenClass {
  /// 820 and up: the sidebar sits in the layout.
  desktop,

  /// 720 to 819: the sidebar becomes a drawer.
  tablet,

  /// Under 720: the same drawer, with roomier controls.
  phone;

  static ScreenClass of(double width) {
    if (width >= 820) return desktop;
    if (width >= 720) return tablet;
    return phone;
  }

  /// The class for the window [context] is in.
  static ScreenClass ofContext(BuildContext context) =>
      of(MediaQuery.sizeOf(context).width);

  bool get isPhone => this == phone;
  bool get sidebarInline => this == desktop;
  bool get sidebarDrawer => !sidebarInline;

  /// Whether the Sources panel sits in the layout at [width], rather than in a drawer.
  static bool sourcesInline(double width) => width >= 1120;
}

abstract final class Sizes {
  static const sidebar = 264.0;
  static const sources = 312.0;
  static const column = 720.0;
  static const card = 16.0;
  static const control = 10.0;
}
