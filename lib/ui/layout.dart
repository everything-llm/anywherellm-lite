import 'package:flutter/widgets.dart';

import 'widgets/window_insets.dart';

abstract final class Sizes {
  /// The widest the chat's turns and composer are laid out, and a page's text beside its list.
  static const column = 760.0;

  /// The least height a pane in `MinHeight` is laid out at; shorter, it scrolls whole.
  static const panelMin = 360.0;

  /// A card's corners.
  static const card = 28.0;

  /// An alert's or a notice's corners, less round than a [card].
  static const notice = 24.0;

  /// The composer's corners.
  static const composer = 28.0;

  /// A row's corners in a list or a menu.
  static const row = 10.0;

  /// A button's or a field's corners.
  static const control = 16.0;

  /// A small button's corners, and a title's press.
  static const small = 12.0;

  /// Around a phone page's cards, under its header.
  static const pagePadding = EdgeInsets.fromLTRB(16, 8, 16, 24);

  /// [pagePadding] with the navigation bar's inset under it, for a page that is not padded by
  /// it and scrolls on through it, so its cards are not cut off above the bar.
  static EdgeInsets pageIn(BuildContext context) => pagePadding.copyWith(
    bottom: pagePadding.bottom + WindowInsets.of(context).bottom,
  );

  /// The least height of a row in a card: a sheet's, a chat's or a document's.
  static const cardRow = 64.0;

  /// The least height of a row in a page's card, whether it opens something, only says
  /// something or holds a switch, as the Lite prototype draws them all.
  static const pageRow = 68.0;

  /// The least height of a page's header bar, which grows with the text.
  static const header = 72.0;

  /// A one-line field's height.
  static const field = 52.0;
}

/// How a wide window is laid out, read from the window's size: a list beside what it opens, an
/// answer's sources beside the chat, and from wider still the chats as a sidebar.
abstract final class Wide {
  /// From this width, with [splitHeight] of height, a list sits beside what it opens and an
  /// answer's sources beside the chat. Narrower, each fills the window in turn.
  static const splitWidth = 840.0;
  static const splitHeight = 480.0;

  /// From this width the chats are a [sidebar] beside everything, in place of the shelf.
  static const sidebarFrom = 1200.0;

  /// The sidebar's width.
  static const sidebar = 256.0;

  /// The width of the panel of an answer's sources beside the chat.
  static const sourcesPanel = 360.0;

  /// Between a list and what it opens, and between the chat and its sources.
  static const gap = 24.0;

  /// A list's width beside what it opens, in [room]: 40% of it, from 320 to 412.
  static double listWidth(double room) => (room * 0.4).clamp(320.0, 412.0);

  /// Whether the window is wide and tall enough for a list beside what it opens.
  static bool split(BuildContext context) => _of(context).split;

  /// Whether the chats show as a sidebar.
  static bool sidebarShown(BuildContext context) => _of(context).sidebar;

  /// What applies to a window of [size].
  static WideLayout at(Size size) => (
    split: size.width >= splitWidth && size.height >= splitHeight,
    sidebar: size.width >= sidebarFrom,
  );

  /// What [WideScope] publishes, or what the window's size gives where there is none.
  static WideLayout _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WideLayout>()?.layout ??
      at(MediaQuery.sizeOf(context));
}

/// Which of a wide window's layouts apply: a list beside what it opens ([Wide.split]), and the
/// chats as a sidebar ([Wide.sidebarShown]).
typedef WideLayout = ({bool split, bool sidebar});

/// Publishes the [WideLayout] of the window to [child], so what reads [Wide.split] or
/// [Wide.sidebarShown] rebuilds only when one of them changes, not on every change of the
/// window's size.
class WideScope extends StatelessWidget {
  const WideScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      _WideLayout(layout: Wide.at(MediaQuery.sizeOf(context)), child: child);
}

class _WideLayout extends InheritedWidget {
  const _WideLayout({required this.layout, required super.child});

  final WideLayout layout;

  @override
  bool updateShouldNotify(_WideLayout old) => layout != old.layout;
}
