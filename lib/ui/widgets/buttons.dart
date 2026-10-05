import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// The button: bordered, with a filled `primary` form.
class NilsButton extends StatelessWidget {
  const NilsButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final phone = ScreenClass.ofContext(context).isPhone;
    final height = phone ? 44.0 : 40.0;
    final fg = primary ? t.onaccent : t.ink;
    return Tappable(
      label: label,
      onTap: onPressed,
      radius: BorderRadius.circular(Sizes.control),
      color: primary ? t.accent : t.panel,
      side: BorderSide(color: primary ? t.accent : t.line),
      hoverColor: primary ? t.onaccent.withValues(alpha: 0.1) : null,
      dimWhenDisabled: 0.5,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: Type.sans(14, weight: FontWeight.w500, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A square icon button with a hover fill.
class IconBtn extends StatelessWidget {
  const IconBtn(
    this.icon, {
    super.key,
    required this.tooltip,
    required this.onPressed,
  });

  final String icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: tooltip,
      tooltip: tooltip,
      onTap: onPressed,
      radius: BorderRadius.circular(8),
      dimWhenDisabled: 0.4,
      child: SizedBox.square(
        dimension: 34,
        child: Center(
          child: NilsIcon(icon, size: IconSize.normal, color: t.ink2),
        ),
      ),
    );
  }
}

/// A chevron and a label that fold something open and shut.
///
/// [label] is what a screen reader hears. [child] is what is drawn beside the chevron.
class Disclosure extends StatelessWidget {
  const Disclosure({
    super.key,
    required this.open,
    required this.onToggle,
    required this.label,
    required this.child,
    this.minHeight = 24,
  });

  final bool open;
  final VoidCallback onToggle;
  final String label;
  final Widget child;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Tappable(
        label: label,
        expanded: open,
        onTap: onToggle,
        radius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NilsIcon(
                'chevron',
                size: IconSize.sm,
                color: t.muted,
                rotated: open,
              ),
              const SizedBox(width: 4),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
