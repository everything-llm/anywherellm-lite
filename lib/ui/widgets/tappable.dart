import 'package:flutter/material.dart';

/// The one way a control is tappable: an optional tooltip, a button's semantics, a surface and
/// an ink well, in that order.
///
/// [label] is what a screen reader hears. [selected], [toggled] and [expanded] say which state
/// the control reports; leave one null when the control has no such state. With no [onTap] the
/// control reports itself disabled, and [dimWhenDisabled] fades it to that opacity.
///
/// The surface is [color] and [side] inside [radius], or [shape] when the outline is not a
/// rounded rectangle. With none of them the control is bare ink over whatever is behind it.
/// [hoverColor] defaults to the theme's.
class Tappable extends StatelessWidget {
  const Tappable({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.selected,
    this.toggled,
    this.expanded,
    this.radius,
    this.shape,
    this.color,
    this.side,
    this.hoverColor,
    this.tooltip,
    this.dimWhenDisabled,
    this.excludeSemantics = true,
  }) : assert(radius == null || shape == null, 'give a radius or a shape');

  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final bool? selected;
  final bool? toggled;
  final bool? expanded;
  final BorderRadius? radius;
  final ShapeBorder? shape;
  final Color? color;
  final BorderSide? side;
  final Color? hoverColor;
  final String? tooltip;

  /// The opacity while [onTap] is null, or null to leave the control as it is.
  final double? dimWhenDisabled;

  /// True hides what [child] says from a screen reader, so [label] is all it hears.
  final bool excludeSemantics;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final outline =
        shape ??
        (radius != null && (color != null || side != null)
            ? RoundedRectangleBorder(
                borderRadius: radius!,
                side: side ?? BorderSide.none,
              )
            : null);
    final ink = InkWell(
      onTap: onTap,
      borderRadius: radius,
      customBorder: shape,
      hoverColor: hoverColor,
      child: child,
    );
    Widget result = Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      toggled: toggled,
      expanded: expanded,
      label: label,
      excludeSemantics: excludeSemantics,
      child: color == null && outline == null
          ? Material(type: MaterialType.transparency, child: ink)
          : Material(
              color: color ?? Colors.transparent,
              shape: outline,
              child: ink,
            ),
    );
    final dim = dimWhenDisabled;
    if (dim != null) {
      result = Opacity(opacity: enabled ? 1 : dim, child: result);
    }
    return tooltip == null ? result : Tooltip(message: tooltip, child: result);
  }
}
