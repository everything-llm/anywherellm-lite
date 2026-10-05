import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import 'buttons.dart';

/// The bar over a main pane: the drawer button when the sidebar is a drawer, the pane's title,
/// and its [actions], which are told when the bar itself is narrow.
class PaneHeader extends StatelessWidget {
  const PaneHeader({
    super.key,
    required this.showMenu,
    required this.onMenu,
    required this.title,
    this.actions,
  });

  /// Whether the bar has a button to open the sidebar drawer.
  final bool showMenu;
  final VoidCallback onMenu;

  /// The title, already styled with [titleStyle] and kept to one line.
  final Widget title;

  /// The widgets after the title, given whether the bar is under 560 wide.
  final List<Widget> Function(bool compact)? actions;

  static TextStyle titleStyle(BuildContext context) =>
      Type.serif(26, color: Tokens.of(context).ink, height: 1.2);

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line2)),
      ),
      // Labels give way to icons when the header itself is narrow, whatever the window.
      child: LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            if (showMenu) ...[
              IconBtn(
                'hamburger',
                tooltip: 'Workspaces',
                size: IconSize.small,
                onPressed: onMenu,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(child: Semantics(header: true, child: title)),
            ...?actions?.call(box.maxWidth < 560),
          ],
        ),
      ),
    );
  }
}
