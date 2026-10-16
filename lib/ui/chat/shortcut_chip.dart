import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import '../type.dart';

/// A shortcut's name as a small accent pill with the slash icon, in the composer while it is
/// chosen and in a sent message that used it.
class ShortcutChip extends StatelessWidget {
  const ShortcutChip(this.label, {super.key, this.maxWidth = double.infinity});

  final String label;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
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
        ],
      ),
    );
  }
}
