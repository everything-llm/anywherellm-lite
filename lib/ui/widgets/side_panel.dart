import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'buttons.dart';
import 'min_height.dart';

/// A panel beside the chat, such as Sources: [title] with [actions] and a close button, the line
/// [about] under it, or after the title when [aboutBeside], and [child] filling the rest. It
/// scrolls whole below [Sizes.panelMin]. A [live] [about] is read out when it changes.
class SidePanel extends StatelessWidget {
  const SidePanel({
    super.key,
    required this.title,
    required this.about,
    required this.onClose,
    required this.child,
    this.width = Sizes.sources,
    this.live = false,
    this.aboutBeside = false,
    this.actions = const [],
  });

  final String title;
  final String about;
  final VoidCallback onClose;
  final Widget child;
  final double width;
  final bool live;
  final bool aboutBeside;

  /// Buttons before the close button, such as one that opens the panel's page elsewhere.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final heading = Semantics(
      header: true,
      child: Text(
        title,
        maxLines: aboutBeside ? 1 : null,
        overflow: aboutBeside ? TextOverflow.ellipsis : null,
        style: Type.sans(15, weight: FontWeight.w600, color: t.ink),
      ),
    );
    final line = Semantics(
      liveRegion: live,
      child: Text(
        about,
        maxLines: aboutBeside ? 1 : null,
        overflow: aboutBeside ? TextOverflow.ellipsis : null,
        style: Type.sans(aboutBeside ? 12.5 : 13, color: t.muted),
      ),
    );
    return Semantics(
      container: true,
      label: title,
      child: MinHeight(
        min: Sizes.panelMin,
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: t.panel2,
            border: Border(left: BorderSide(color: t.line)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: aboutBeside
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Flexible(child: heading),
                              const SizedBox(width: 8),
                              Flexible(child: line),
                            ],
                          )
                        : heading,
                  ),
                  ...actions,
                  IconBtn(
                    'close',
                    tooltip: 'Close',
                    box: 28,
                    size: IconSize.xs,
                    onPressed: onClose,
                  ),
                ],
              ),
              if (!aboutBeside) ...[const SizedBox(height: 4), line],
              const SizedBox(height: 14),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
