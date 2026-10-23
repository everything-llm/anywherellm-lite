import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'buttons.dart';
import 'tappable.dart';

/// The bar over a phone's full page: a round back button floating on the tile, heard as
/// [back], [title] centred as [Type.title], or [heading] in its place, and at most one round
/// [action] at its end.
class PhonePageHeader extends StatelessWidget {
  const PhonePageHeader({
    super.key,
    this.title = '',
    this.heading,
    required this.back,
    required this.onBack,
    this.backIcon = 'back',
    this.action,
  });

  final String title;

  /// What the bar shows between its buttons in place of [title], such as the chat's name.
  final Widget? heading;

  /// What the back button is heard as, such as Back to the chat.
  final String back;

  /// Null leaves the back button's room empty, as on a guide's first screen.
  final VoidCallback? onBack;

  /// The back button's icon: an arrow, or the chat's menu, which opens the Chats shelf.
  final String backIcon;

  /// A button at the bar's end, such as Download.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Sizes.header),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            if (onBack case final onBack?)
              IconBtn.header(backIcon, tooltip: back, onPressed: onBack)
            else
              const SizedBox(width: 48),
            const SizedBox(width: 4),
            Expanded(
              child:
                  heading ??
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Type.title(t.ink),
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

/// A row that opens another page: an [icon] at 24, [title] as [Type.body], the line [about]
/// under it at 13 in ink, and a chevron, or the [end] icon in its place.
class NavRow extends StatelessWidget {
  const NavRow({
    super.key,
    required this.title,
    required this.onTap,
    this.about,
    this.aboutSpan,
    this.aboutLines = 1,
    this.failed = false,
    this.heard,
    this.icon,
    this.lead,
    this.end = 'chevron',
    this.accent = false,
    this.mono = false,
    this.selected,
  });

  final String title;
  final String? about;

  /// The line under [title] as styled text, in place of [about].
  final InlineSpan? aboutSpan;

  /// How many lines [about] may take before it is cut short.
  final int aboutLines;

  /// Whether [about] says something failed, which a [Tokens.danger] mark goes before.
  final bool failed;
  final VoidCallback? onTap;

  /// An icon before [title], as Settings' rows have.
  final String? icon;

  /// What stands before [title] in place of an [icon].
  final Widget? lead;

  /// The icon the row ends in, such as `external` for a page outside the app, or none.
  final String? end;

  /// Whether [title] is in the accent, as a link out of the app is.
  final bool accent;

  /// Whether [title] is in the mono face, as an address is.
  final bool mono;

  /// What a screen reader hears, when it says more than [title] and [about].
  final String? heard;

  /// Whether a screen reader hears the row as the one chosen, when it is one of a choice.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final ink = accent ? t.accent : t.ink;
    return Tappable(
      label: heard ?? [title, ?about].join(', '),
      selected: selected,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: Sizes.pageRow),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            if (lead case final lead?) ...[
              lead,
              const SizedBox(width: 16),
            ] else if (icon case final icon?) ...[
              AppIcon(icon, size: IconSize.large, color: t.ink),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: mono ? Type.mono(15, color: ink) : Type.body(ink),
                  ),
                  if (aboutSpan ??
                          (about?.isNotEmpty ?? false
                              ? TextSpan(text: about)
                              : null)
                      case final about?)
                    Row(
                      children: [
                        if (failed) ...[
                          AppIcon(
                            'failed',
                            size: IconSize.small,
                            color: t.danger,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text.rich(
                            about,
                            maxLines: aboutLines,
                            overflow: TextOverflow.ellipsis,
                            style: Type.note(t.ink),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (end case final end?) ...[
              const SizedBox(width: 8),
              AppIcon(
                end,
                size: end == 'chevron' ? IconSize.xs : IconSize.small,
                color: t.muted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
