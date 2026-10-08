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
    this.active,
  });

  final String icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Whether a button that toggles something is on. Null for one that does not toggle.
  final bool? active;

  /// The side of the square.
  final double box;
  final IconSize size;

  /// A destructive action: the bad colour fills it on hover.
  final bool dangerHover;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      touchTarget: true,
      label: tooltip,
      tooltip: tooltip,
      onTap: onPressed,
      toggled: active,
      radius: BorderRadius.circular(box <= 32 ? 6 : 8),
      color: active == true ? t.accentbg : null,
      hoverColor: dangerHover ? t.badbg : null,
      dimWhenDisabled: 0.4,
      child: SizedBox.square(
        dimension: box,
        child: Center(
          child: AppIcon(
            icon,
            size: size,
            color: active == true ? t.accent : t.ink2,
          ),
        ),
      ),
    );
  }
}

/// A form's buttons, such as Cancel and Add, in a row at its end that wraps when narrow.
class ActionRow extends StatelessWidget {
  const ActionRow(this.children, {super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.end,
    spacing: 8,
    runSpacing: 8,
    children: children,
  );
}

/// A small text button with an icon before it.
class TextAction extends StatelessWidget {
  const TextAction(
    this.icon,
    this.label,
    this.onTap, {
    super.key,
    this.semanticLabel,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  /// What a screen reader hears, when [label] alone is not enough, as in a list.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: semanticLabel ?? label,
      onTap: onTap,
      radius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: IconSize.xs, color: t.accent),
            const SizedBox(width: 6),
            Text(label, style: Type.sans(13, color: t.accent)),
          ],
        ),
      ),
    );
  }
}
