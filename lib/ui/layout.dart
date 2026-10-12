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

  /// Whether Settings shows its list beside a page at [width], rather than one, then the other.
  static bool settingsSideBySide(double width) =>
      width >= Sizes.settingsSideBySide;
}

abstract final class Sizes {
  static const sidebar = 264.0;
  static const sources = 312.0;

  static const column = 720.0;

  /// The least height a pane in `MinHeight` is laid out at; shorter, it scrolls whole.
  static const panelMin = 360.0;

  /// A card's or a panel's corners.
  static const card = 20.0;

  /// A grouped card's corners on a phone, rounder than [card].
  static const phoneCard = 24.0;

  /// The composer's corners.
  static const composer = 24.0;

  /// The composer's corners on a phone.
  static const phoneComposer = 28.0;

  /// A menu's corners.
  static const menu = 16.0;

  /// A row's corners in a list or a menu.
  static const row = 10.0;
  static const control = 12.0;

  /// A button's or a field's corners on a phone, rounder than [control].
  static const phoneControl = 16.0;

  /// A button's or a field's corners in the window [context] is in.
  static double controlOf(BuildContext context) =>
      ScreenClass.ofContext(context).isPhone ? phoneControl : control;

  /// A card's corners in the window [context] is in.
  static double cardOf(BuildContext context) =>
      ScreenClass.ofContext(context).isPhone ? phoneCard : card;

  /// A one-line field's height in the window [context] is in: taller on a phone.
  static double fieldOf(BuildContext context) =>
      ScreenClass.ofContext(context).isPhone ? 52 : 44;

  /// The least width at which Settings shows its list and a page side by side.
  static const settingsSideBySide = 820.0;

  /// Settings' list of pages, beside a page.
  static const settingsNav = 236.0;
}
