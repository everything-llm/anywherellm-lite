import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/tappable.dart';

/// A pill in the composer's row that names a setting and opens what changes it, such as the
/// Answer from menu or the model picker: 26 px tall with a chevron, or 28 px and without one on
/// a phone, where the row has less room. [tinted] fills it with the accent, for a setting that
/// changes how answers read. A null [onTap] fades it.
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
    final phone = ScreenClass.ofContext(context).isPhone;
    final ink = tinted ? t.accent : t.ink2;
    return Tappable(
      touchTarget: true,
      label: label,
      tooltip: tooltip,
      expanded: open,
      onTap: onTap,
      dimWhenDisabled: 0.4,
      radius: BorderRadius.circular(99),
      color: tinted
          ? t.accentbg
          : open
          ? t.hover
          : Colors.transparent,
      side: BorderSide(color: tinted ? Colors.transparent : t.line),
      child: SizedBox(
        height: phone ? 28 : 26,
        child: Padding(
          padding: EdgeInsets.only(left: 9, right: phone ? 9 : 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sans(
                    12.5,
                    weight: tinted ? FontWeight.w600 : FontWeight.w400,
                    color: ink,
                  ),
                ),
              ),
              if (!phone) ...[
                const SizedBox(width: 4),
                AppIcon('down', size: IconSize.tiny, color: ink),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
