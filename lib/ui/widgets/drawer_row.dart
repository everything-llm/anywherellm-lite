import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// A row of a phone's drawer, in one of its cards: an icon, [title] and, at the end, [trailing].
/// A screen reader hears [heard]. [accent] draws it in the accent, as New chat is.
class DrawerRow extends StatelessWidget {
  const DrawerRow({
    super.key,
    required this.icon,
    required this.title,
    required this.heard,
    required this.onTap,
    this.trailing,
    this.accent = false,
  });

  final String icon;
  final String title;
  final String heard;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: heard,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            spacing: 16,
            children: [
              AppIcon(icon, color: accent ? t.accent : t.ink2),
              Expanded(
                child: Text(
                  title,
                  style: Type.sans(
                    17,
                    weight: accent ? FontWeight.w600 : FontWeight.w400,
                    color: accent ? t.accent : t.ink,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
