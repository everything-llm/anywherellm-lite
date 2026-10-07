import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'buttons.dart';
import 'min_height.dart';

/// A panel beside the chat, such as Sources: [title] with a close button, the line [about]
/// under it, and [child] filling the rest. It scrolls whole below [Sizes.panelMin]. A [live]
/// [about] is read out when it changes.
class SidePanel extends StatelessWidget {
  const SidePanel({
    super.key,
    required this.title,
    required this.about,
    required this.onClose,
    required this.child,
    this.width = Sizes.sources,
    this.live = false,
  });

  final String title;
  final String about;
  final VoidCallback onClose;
  final Widget child;
  final double width;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
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
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: Type.sans(
                          15,
                          weight: FontWeight.w600,
                          color: t.ink,
                        ),
                      ),
                    ),
                  ),
                  IconBtn(
                    'close',
                    tooltip: 'Close',
                    box: 28,
                    size: IconSize.xs,
                    onPressed: onClose,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Semantics(
                liveRegion: live,
                child: Text(about, style: Type.sans(13, color: t.muted)),
              ),
              const SizedBox(height: 14),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
