import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// A row of a phone's drawer that opens a page: an icon, [title] and, at the end, [trailing].
/// A screen reader hears [heard].
class DrawerRow extends StatelessWidget {
  const DrawerRow({
    super.key,
    required this.icon,
    required this.title,
    required this.heard,
    required this.onTap,
    this.trailing,
  });

  final String icon;
  final String title;
  final String heard;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: heard,
      onTap: onTap,
      radius: BorderRadius.circular(10),
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              AppIcon(icon, size: IconSize.small, color: t.ink2),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Type.sans(15, weight: FontWeight.w500, color: t.ink),
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
