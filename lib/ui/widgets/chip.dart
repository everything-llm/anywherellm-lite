import 'package:flutter/material.dart';

import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// A tag that filters a list: a label and, when known, how many items it would show. [pressed]
/// fills it in the accent. [dim] fades a tag that would show nothing more.
class NilsChip extends StatelessWidget {
  const NilsChip(
    this.label, {
    super.key,
    required this.pressed,
    required this.onTap,
    this.count,
    this.dim = false,
  });

  final String label;
  final bool pressed;
  final VoidCallback onTap;
  final int? count;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final phone = ScreenClass.ofContext(context).isPhone;
    final ink = pressed ? t.onaccent : t.ink2;
    return Opacity(
      opacity: dim ? 0.5 : 1,
      child: Tappable(
        label: count == null ? label : '$label, $count',
        toggled: pressed,
        onTap: onTap,
        shape: StadiumBorder(
          side: BorderSide(color: pressed ? t.accent : t.line),
        ),
        color: pressed ? t.accent : t.panel,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: phone ? 44 : 32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sans(13, color: ink),
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: Type.sans(12, color: pressed ? t.onaccent : t.muted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
