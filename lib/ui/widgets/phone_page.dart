import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import 'buttons.dart';
import 'tappable.dart';

/// The bar over a phone's full page: a round back button, heard as [back], [title] centred at
/// 19, and at most one round [action] at its end.
class PhonePageHeader extends StatelessWidget {
  const PhonePageHeader({
    super.key,
    required this.title,
    required this.back,
    required this.onBack,
    this.action,
  });

  final String title;

  /// What the back button is heard as, such as Back to the chat.
  final String back;
  final VoidCallback onBack;

  /// A button at the bar's end, such as Download.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return SizedBox(
      height: 72,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            IconBtn(
              'back',
              tooltip: back,
              box: 48,
              filled: true,
              size: IconSize.small,
              onPressed: onBack,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Type.sans(19, weight: FontWeight.w600, color: t.ink),
                ),
              ),
            ),
            const SizedBox(width: 4),
            action ?? const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}

/// A row that opens another page: [title], the line [about] under it, and a chevron.
class NavRow extends StatelessWidget {
  const NavRow({
    super.key,
    required this.title,
    required this.onTap,
    this.about,
    this.heard,
    this.icon,
    this.chevron = true,
  });

  final String title;
  final String? about;
  final VoidCallback? onTap;

  /// An icon before [title], as Settings' rows have.
  final String? icon;

  /// Whether the row ends in a chevron.
  final bool chevron;

  /// What a screen reader hears, when it says more than [title] and [about].
  final String? heard;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: heard ?? [title, ?about].join(', '),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            if (icon case final icon?) ...[
              AppIcon(icon, color: t.ink2),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Type.sans(17, weight: FontWeight.w500, color: t.ink),
                  ),
                  if (about case final about? when about.isNotEmpty)
                    Text(
                      about,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.sans(13, color: t.muted),
                    ),
                ],
              ),
            ),
            if (chevron) ...[
              const SizedBox(width: 8),
              AppIcon('chevron', size: IconSize.xs, color: t.muted),
            ],
          ],
        ),
      ),
    );
  }
}
