import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// The button: bordered, with a filled `primary` form.
class AppButton extends StatelessWidget {
  const AppButton(
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
    this.box = 34,
    this.size = IconSize.normal,
    this.dangerHover = false,
  });

  final String icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// The side of the square.
  final double box;
  final IconSize size;

  /// A destructive action: the bad colour fills it on hover.
  final bool dangerHover;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: tooltip,
      tooltip: tooltip,
      onTap: onPressed,
      radius: BorderRadius.circular(box < 30 ? 6 : 8),
      hoverColor: dangerHover ? t.badbg : null,
      dimWhenDisabled: 0.4,
      child: SizedBox.square(
        dimension: box,
        child: Center(
          child: AppIcon(icon, size: size, color: t.ink2),
        ),
      ),
    );
  }
}
