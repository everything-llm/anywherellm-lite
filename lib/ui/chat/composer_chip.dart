import 'package:flutter/material.dart';

import '../tokens.dart';
import '../type.dart';
import '../widgets/tappable.dart';

/// A pill in the composer's row that names a setting and opens what changes it, such as the
/// Answer from menu or the model picker: 28 px tall, without a chevron, since the row has little
/// room. [tinted] fills it with the accent, for a setting that
/// changes how answers read. A null [onTap] shows it disabled, opaque: muted words on a sunken
/// fill inside a line.
class ComposerChip extends StatelessWidget {
  const ComposerChip({
    super.key,
    required this.text,
    required this.label,
    required this.onTap,
    this.tooltip,
    this.open = false,
    this.tinted = false,
  });

  final String text;

  /// What a screen reader hears.
  final String label;
  final String? tooltip;
  final VoidCallback? onTap;

  /// Whether what it opens shows.
  final bool open;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final enabled = onTap != null;
    final ink = !enabled
        ? t.muted
        : tinted
        ? t.accent
        : t.ink;
    return Tappable(
      touchTarget: true,
      label: label,
      tooltip: tooltip,
      expanded: open,
      onTap: onTap,
      radius: BorderRadius.circular(99),
      color: !enabled
          ? t.sunken
          : tinted
          ? t.accentSoft
          : open
          ? t.sunken
          : Colors.transparent,
      side: BorderSide(color: tinted && enabled ? Colors.transparent : t.line),
      child: SizedBox(
        height: 28,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.caption(
                    ink,
                    weight: tinted ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
