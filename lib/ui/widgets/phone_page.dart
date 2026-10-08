import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import 'buttons.dart';
import 'tappable.dart';

/// The bar over a phone's full page: a 44 px back button, heard as [back], and [title] in the
/// serif at 26.
class PhonePageHeader extends StatelessWidget {
  const PhonePageHeader({
    super.key,
    required this.title,
    required this.back,
    required this.onBack,
    this.actions = const [],
  });

  final String title;

  /// What the back button is heard as, such as Back to the chat.
  final String back;
  final VoidCallback onBack;

  /// Buttons at the bar's end.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      height: 60,
      padding: const EdgeInsets.only(left: 4, right: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line2)),
      ),
      child: Row(
        children: [
          IconBtn(
            'back',
            tooltip: back,
            box: 44,
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
                style: Type.serif(
                  26,
                  color: t.ink,
                  height: 1.2,
                  letterSpacing: -0.4,
                ),
              ),
            ),
          ),
          ...actions,
        ],
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
  });

  final String title;
  final String? about;
  final VoidCallback? onTap;

  /// What a screen reader hears, when it says more than [title] and [about].
  final String? heard;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: heard ?? [title, ?about].join(', '),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Type.sans(
                      15.5,
                      weight: FontWeight.w500,
                      color: t.ink,
                    ),
                  ),
                  if (about case final about? when about.isNotEmpty)
                    Text(
                      about,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.sans(12.5, color: t.muted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AppIcon('chevron', size: IconSize.xs, color: t.muted),
          ],
        ),
      ),
    );
  }
}
