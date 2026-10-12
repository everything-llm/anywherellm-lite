import 'package:flutter/material.dart';

import 'sheet.dart';

/// A panel over the chat, such as Sources: a [SheetFrame] [sheetHeight] tall with [title],
/// [actions] and a close button, the line [about], when there is one, under it, and [child]
/// filling the rest. A [live] [about] is read out when it changes.
class SidePanel extends StatelessWidget {
  const SidePanel({
    super.key,
    required this.title,
    this.about,
    required this.onClose,
    required this.child,
    this.live = false,
    this.actions = const [],
    this.sheetHeight = SheetHeight.tall,
  });

  final String title;
  final String? about;
  final VoidCallback onClose;
  final Widget child;
  final bool live;

  /// Buttons before the close button, such as one that opens the panel's page elsewhere.
  final List<Widget> actions;

  final SheetHeight sheetHeight;

  @override
  Widget build(BuildContext context) => SheetFrame(
    title: title,
    about: about,
    live: live,
    actions: actions,
    onClose: onClose,
    height: sheetHeight,
    child: child,
  );
}
