import 'package:flutter/material.dart';

import '../icons.dart';
import '../widgets/buttons.dart';
import '../tokens.dart';
import '../type.dart';

/// A shortcut's name as a small accent pill with the slash icon, in the composer while it is
/// chosen and in a sent message that used it.
class ShortcutChip extends StatelessWidget {
  const ShortcutChip(
    this.label, {
    super.key,
    this.maxWidth = double.infinity,
    this.onClear,
  });

  final String label;
  final double maxWidth;

  /// Takes the chip away, shown as a close button in it, or null for a chip that stays.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: EdgeInsets.only(
        left: 9,
        right: onClear == null ? 9 : 2,
        top: onClear == null ? 6 : 0,
        bottom: onClear == null ? 6 : 0,
      ),
      decoration: BoxDecoration(
        color: t.accentbg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          AppIcon('slash', size: IconSize.tiny, color: t.accent),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.sans(12, color: t.accent),
            ),
          ),
          if (onClear case final clear?)
            IconBtn(
              'close',
              tooltip: 'Remove the $label shortcut',
              onPressed: clear,
              box: 32,
              size: IconSize.tiny,
            ),
        ],
      ),
    );
  }
}
