import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// A row of a phone's drawer, flat on its ground: an icon, [title] and, at the end, [trailing].
/// A screen reader hears [heard], and [selected] when it is given. [strong] sets the title in
/// semibold, as a workspace the search found is.
class DrawerRow extends StatelessWidget {
  const DrawerRow({
    super.key,
    required this.icon,
    required this.title,
    required this.heard,
    required this.onTap,
    this.trailing,
    this.iconSize = IconSize.normal,
    this.selected,
    this.strong = false,
  });

  final String icon;
  final String title;
  final String heard;
  final VoidCallback onTap;
  final Widget? trailing;
  final IconSize iconSize;
  final bool? selected;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: heard,
      selected: selected,
      onTap: onTap,
      radius: BorderRadius.circular(Sizes.control),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            spacing: 12,
            children: [
              AppIcon(icon, size: iconSize, color: t.ink2),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sans(
                    15.5,
                    weight: strong ? FontWeight.w600 : FontWeight.w400,
                    color: t.ink,
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

/// What a [DrawerRow] counts at its end, such as `1 running`.
class DrawerCount extends StatelessWidget {
  const DrawerCount(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Type.sans(12.5, color: Tokens.of(context).muted));
}
