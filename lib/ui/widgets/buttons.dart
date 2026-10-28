import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// House UI's button: the `primary` one a pill on the accent with its glow, 48 tall, for the one
/// action a screen exists for; any other on the tile inside a [Tokens.lineStrong] edge, 44
/// tall, or [danger] inside a [Tokens.danger] one. Each is tapped in at least
/// [Tappable.touchSide], so a 44 tall one takes taps 2 past its edge above and below. Its label
/// is 16 at 600 and wraps rather than truncating. Disabled, it stays readable on [Tokens.sunken]. In an [ActionRow.even] it keeps
/// 8 px either side of its label rather than 16.
class AppButton extends StatelessWidget {
  const AppButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.primary = false,
    this.danger = false,
    this.quiet = false,
    this.icon,
    this.leading,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  /// A primary button 44 tall, as every other button is, for two side by side inside a card.
  final bool compact;

  /// A destructive action: its label and edge in [Tokens.danger], never filled.
  final bool danger;

  /// A button with no edge or fill, for an action that should not weigh as much as the ones
  /// around it.
  final bool quiet;

  /// An icon after the label, such as `external` for a button that leaves the app.
  final String? icon;

  /// An icon before the label, such as `qr` for the button that scans a code.
  final String? leading;

  /// The height of every button but a full-size primary one.
  static const height = 44.0;

  /// A primary button's height.
  static const primaryHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final enabled = onPressed != null;
    final pill = primary && enabled;
    final fg = !enabled
        ? t.muted
        : primary
        ? t.onAccent
        : danger
        ? t.danger
        : quiet
        ? t.accent
        : t.ink;
    final edge = !enabled
        ? t.line
        : primary
        ? t.accent
        : danger
        ? t.danger
        : t.lineStrong;
    final radius = BorderRadius.circular(primary ? 999 : Sizes.control);
    return Tappable(
      touchTarget: true,
      label: label,
      onTap: onPressed,
      radius: radius,
      color: !enabled
          ? t.sunken
          : primary
          ? t.accent
          : quiet
          ? Colors.transparent
          : t.tile,
      side: quiet && enabled ? BorderSide.none : BorderSide(color: edge),
      hoverColor: primary ? t.onAccent.withValues(alpha: 0.1) : null,
      shadows: pill ? t.glow : const [],
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: primary && !compact ? primaryHeight : height,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: _EvenRow.holds(context)
                ? 8
                : primary
                ? 24
                : 16,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading case final leading?) ...[
                AppIcon(leading, size: IconSize.medium, color: fg),
                const SizedBox(width: 8),
              ],
              // A label wider than the space wraps rather than overflows.
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Type.label(fg),
                ),
              ),
              if (icon case final icon?) ...[
                const SizedBox(width: 8),
                AppIcon(icon, size: IconSize.small, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A round icon button with a hover fill, or with [filled] a round button on the hover colour,
/// as a phone's header draws them.
class IconBtn extends StatelessWidget {
  const IconBtn(
    this.icon, {
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.box = 34,
    this.size = IconSize.normal,
    this.active,
    this.filled = false,
    this.heard,
    this.expanded,
  });

  /// A header's round button: 48 across, floating on the tile, its icon at [IconSize.small].
  const IconBtn.header(
    this.icon, {
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.active,
    this.heard,
    this.expanded,
  }) : box = 48,
       filled = true,
       size = IconSize.small;

  final String icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Whether a button that toggles something is on. Null for one that does not toggle.
  final bool? active;

  /// The button's diameter.
  final double box;

  /// Whether it floats on the tile with a tile's shadow, as a bar's buttons do.
  final bool filled;

  /// What a screen reader hears, when it says more than [tooltip].
  final String? heard;

  /// Whether what the button opens is open, for one that opens a menu. Null for one that does
  /// not.
  final bool? expanded;
  final IconSize size;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final enabled = onPressed != null;
    final floats = filled && active != true && enabled;
    // Disabled, it stays opaque: a muted icon, and a filled one sunken inside a line.
    return Tappable(
      touchTarget: true,
      label: heard ?? tooltip,
      tooltip: tooltip,
      onTap: onPressed,
      toggled: active,
      expanded: expanded,
      shape: CircleBorder(
        side: floats
            ? BorderSide(color: t.tileEdge)
            : filled && !enabled
            ? BorderSide(color: t.line)
            : BorderSide.none,
      ),
      shadows: floats ? t.tileShadow : const [],
      color: !enabled
          ? (filled ? t.sunken : null)
          : active == true
          ? t.accentSoft
          : filled
          ? t.tile
          : null,
      child: SizedBox.square(
        dimension: box,
        child: Center(
          child: AppIcon(
            icon,
            size: size,
            color: !enabled
                ? t.muted
                : active == true
                ? t.accent
                : t.ink,
          ),
        ),
      ),
    );
  }
}

/// The Save and Revert buttons of a form, for an [ActionRow]: Save reads Saving… while [saving],
/// and both wait for a change ([dirty]) and for any save to end. Revert comes first.
List<Widget> saveRevertButtons({
  required bool dirty,
  required bool saving,
  required VoidCallback onSave,
  required VoidCallback onRevert,
}) {
  final ready = dirty && !saving;
  return [
    AppButton('Revert', onPressed: ready ? onRevert : null),
    AppButton(
      saving ? 'Saving…' : 'Save',
      primary: true,
      onPressed: ready ? onSave : null,
    ),
  ];
}

/// A form's buttons, such as Cancel and Add, in a row at its end that wraps when narrow. A
/// page's own buttons under its cards sit from the start of the line ([WrapAlignment.start]).
/// [even] shares the line between them in equal widths, as a phone's card does.
class ActionRow extends StatelessWidget {
  const ActionRow(
    this.children, {
    super.key,
    this.alignment = WrapAlignment.end,
    this.even = false,
  });

  final List<Widget> children;
  final WrapAlignment alignment;
  final bool even;

  @override
  Widget build(BuildContext context) {
    if (!even) {
      return Wrap(
        alignment: alignment,
        spacing: 8,
        runSpacing: 8,
        children: children,
      );
    }
    return _EvenRow(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [for (final child in children) Expanded(child: child)],
      ),
    );
  }
}

/// Marks the buttons of an [ActionRow.even], which share the line in equal widths.
class _EvenRow extends InheritedWidget {
  const _EvenRow({required super.child});

  static bool holds(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_EvenRow>() != null;

  @override
  bool updateShouldNotify(_EvenRow old) => false;
}

/// A small text button, its words at 13 in the accent, with an icon before it, or only its words
/// ([TextAction.plain]).
class TextAction extends StatelessWidget {
  const TextAction(
    String this.icon,
    this.label,
    this.onTap, {
    super.key,
    this.semanticLabel,
  });

  const TextAction.plain(
    this.label,
    this.onTap, {
    super.key,
    this.semanticLabel,
  }) : icon = null;

  final String? icon;
  final String label;
  final VoidCallback onTap;

  /// What a screen reader hears, when [label] alone is not enough, as in a list.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon case final icon?) ...[
          AppIcon(icon, size: IconSize.small, color: t.accent),
          const SizedBox(width: 6),
        ],
        // Wraps where the line is too narrow for it.
        Flexible(
          child: Text(
            label,
            style: Type.caption(t.accent, weight: FontWeight.w600),
          ),
        ),
      ],
    );
    return Tappable(
      label: semanticLabel ?? label,
      onTap: onTap,
      radius: BorderRadius.circular(6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Tappable.touchSide),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Align(widthFactor: 1, heightFactor: 1, child: content),
        ),
      ),
    );
  }
}
