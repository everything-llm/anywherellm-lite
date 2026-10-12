import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// The button: bordered, with a filled `primary` form, 52 tall with its label at 16, as the
/// design canvas draws it. In an [ActionRow.even] it keeps 8 px either side of its
/// label rather than 16.
class AppButton extends StatelessWidget {
  const AppButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.primary = false,
    this.danger = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  /// A destructive action that is not the primary one: its label in [Tokens.badfg].
  final bool danger;

  /// An icon after the label, such as `external` for a button that leaves the app.
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    const height = 52.0;
    final fg = primary
        ? t.onaccent
        : danger
        ? t.badfg
        : t.ink;
    return Tappable(
      label: label,
      onTap: onPressed,
      radius: BorderRadius.circular(Sizes.phoneControl),
      color: primary ? t.accent : t.panel,
      side: BorderSide(color: primary ? t.accent : t.line),
      hoverColor: primary ? t.onaccent.withValues(alpha: 0.1) : null,
      dimWhenDisabled: 0.5,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: _EvenRow.holds(context) ? 8 : 16,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // A label wider than the space wraps rather than overflows.
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Type.sans(16, weight: FontWeight.w500, color: fg),
                ),
              ),
              if (icon case final icon?) ...[
                const SizedBox(width: 8),
                AppIcon(icon, size: IconSize.xs, color: fg),
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

  final String icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Whether a button that toggles something is on. Null for one that does not toggle.
  final bool? active;

  /// The button's diameter.
  final double box;

  /// Whether it sits on [Tokens.hover] with its icon in [Tokens.ink].
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
    return Tappable(
      touchTarget: true,
      label: heard ?? tooltip,
      tooltip: tooltip,
      onTap: onPressed,
      toggled: active,
      expanded: expanded,
      shape: const CircleBorder(),
      color: active == true
          ? t.accentbg
          : filled
          ? t.hover
          : null,
      dimWhenDisabled: 0.4,
      child: SizedBox.square(
        dimension: box,
        child: Center(
          child: AppIcon(
            icon,
            size: size,
            color: active == true
                ? t.accent
                : filled
                ? t.ink
                : t.ink2,
          ),
        ),
      ),
    );
  }
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

/// A small text button in the accent, with an icon before it, or only its words
/// ([TextAction.plain]).
class TextAction extends StatelessWidget {
  const TextAction(
    String this.icon,
    this.label,
    this.onTap, {
    super.key,
    this.semanticLabel,
    this.height,
  });

  const TextAction.plain(
    this.label,
    this.onTap, {
    super.key,
    this.semanticLabel,
    this.height,
  }) : icon = null;

  final String? icon;
  final String label;
  final VoidCallback onTap;

  /// What a screen reader hears, when [label] alone is not enough, as in a list.
  final String? semanticLabel;

  /// The least height, with the words in its middle, as beside buttons whose row it shares.
  /// It is at least 44.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final height = math.max(44.0, this.height ?? 0);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon case final icon?) ...[
          AppIcon(icon, size: IconSize.small, color: t.accent),
          const SizedBox(width: 6),
        ],
        // Wraps where the line is too narrow for it.
        Flexible(
          child: Text(label, style: Type.sans(14, color: t.accent)),
        ),
      ],
    );
    return Tappable(
      label: semanticLabel ?? label,
      onTap: onTap,
      radius: BorderRadius.circular(6),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Align(widthFactor: 1, heightFactor: 1, child: content),
        ),
      ),
    );
  }
}
