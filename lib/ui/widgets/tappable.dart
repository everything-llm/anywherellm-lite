import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The one way a control is tappable: an optional tooltip, a button's semantics, a surface and
/// an ink well, in that order.
///
/// [label] is what a screen reader hears. [selected], [toggled] and [expanded] say which state
/// the control reports; leave one null when the control has no such state. With no [onTap] the
/// control reports itself disabled, and [dimWhenDisabled] fades it to that opacity.
///
/// The surface is [color] and [side] inside [radius], or [shape] when the outline is not a
/// rounded rectangle. With none of them the control is bare ink over whatever is behind it.
/// [hoverColor] defaults to the theme's. [shadows] fall from the surface's own outline, as a
/// floating button's or the primary action's glow do.
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
    this.shadows = const [],
    this.tooltip,
    this.dimWhenDisabled,
    this.excludeSemantics = true,
    this.touchTarget = false,
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
  final List<BoxShadow> shadows;
  final String? tooltip;

  /// The opacity while [onTap] is null, or null to leave the control as it is.
  final double? dimWhenDisabled;

  /// True hides what [child] says from a screen reader, so [label] is all it hears.
  final bool excludeSemantics;

  /// True gives a control drawn smaller than a finger a square of [touchSide] to be tapped in,
  /// where a tap beside it does what [onTap] does. The control keeps the constraints it is
  /// given, so one that fills the width it is given, as a button in an even row does, still
  /// fills it.
  final bool touchTarget;

  /// The least a finger needs: House UI's `size-target-touch`, as Android's 48 dp is. A control
  /// may be drawn smaller, as a 44 tall button is; its hit area is never smaller than this.
  static const touchSide = 48.0;

  /// [surface] over [shadows] in the shape of its [outline], whose edge it does not draw again.
  Widget _shadowed(ShapeBorder? outline, Widget surface) {
    if (shadows.isEmpty) return surface;
    final shape = switch (outline) {
      final OutlinedBorder o => o.copyWith(side: BorderSide.none),
      final other? => other,
      null => RoundedRectangleBorder(borderRadius: radius ?? BorderRadius.zero),
    };
    return DecoratedBox(
      decoration: ShapeDecoration(shape: shape, shadows: shadows),
      child: surface,
    );
  }

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
      child: _shadowed(
        outline,
        color == null && outline == null
            ? Material(type: MaterialType.transparency, child: ink)
            : Material(
                color: color ?? Colors.transparent,
                shape: outline,
                child: ink,
              ),
      ),
    );
    final dim = dimWhenDisabled;
    if (dim != null) {
      result = Opacity(opacity: enabled ? 1 : dim, child: result);
    }
    if (tooltip != null) result = Tooltip(message: tooltip, child: result);
    // Its own node with its tooltip, so its label and bounds never merge into what holds it.
    result = Semantics(container: true, child: result);
    if (!touchTarget) return result;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // The control already says what it is and does.
      excludeFromSemantics: true,
      child: _TouchBox(child: result),
    );
  }
}

/// [child] centred in a box at least [Tappable.touchSide] square. Unlike a [ConstrainedBox] over
/// a [Center], it hands [child] the constraints it is given unloosened, so a control given a
/// tight width keeps it.
class _TouchBox extends SingleChildRenderObjectWidget {
  const _TouchBox({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTouchBox();
}

class _RenderTouchBox extends RenderShiftedBox {
  _RenderTouchBox() : super(null);

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(const Size.square(Tappable.touchSide));
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(
      Size(
        math.max(child.size.width, Tappable.touchSide),
        math.max(child.size.height, Tappable.touchSide),
      ),
    );
    (child.parentData! as BoxParentData).offset = Alignment.center.alongOffset(
      size - child.size as Offset,
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(super.computeMinIntrinsicWidth(height), Tappable.touchSide);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max(super.computeMaxIntrinsicWidth(height), Tappable.touchSide);

  @override
  double computeMinIntrinsicHeight(double width) =>
      math.max(super.computeMinIntrinsicHeight(width), Tappable.touchSide);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      math.max(super.computeMaxIntrinsicHeight(width), Tappable.touchSide);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child?.getDryLayout(constraints) ?? Size.zero;
    return constraints.constrain(
      Size(
        math.max(child.width, Tappable.touchSide),
        math.max(child.height, Tappable.touchSide),
      ),
    );
  }
}
