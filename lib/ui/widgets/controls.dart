import 'package:flutter/material.dart';

import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';
import 'rise.dart';

enum BadgeKind { ok, warn, accent }

/// A small rounded label: a status, or a count.
class AppBadge extends StatelessWidget {
  const AppBadge(this.text, {super.key, required this.kind, this.pill = false});

  final String text;
  final BadgeKind kind;

  /// Fully rounded, for a count.
  final bool pill;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final (fg, bg) = switch (kind) {
      BadgeKind.ok => (t.okfg, t.okbg),
      BadgeKind.warn => (t.warnfg, t.warnbg),
      BadgeKind.accent => (t.accent, t.accentbg),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: pill ? 7 : 8,
        vertical: pill ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(pill ? 99 : 6),
      ),
      child: Text(text, style: Type.sans(12, height: 1.4, color: fg)),
    );
  }
}

/// An on and off switch: a track with a knob, the accent when on.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.tooltip,
    this.large = false,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// What a screen reader hears.
  final String label;
  final String? tooltip;

  /// The 38 by 22 track of a settings row, rather than the 34 by 20 of a file row.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return Tappable(
      label: label,
      toggled: value,
      tooltip: tooltip,
      onTap: change == null ? null : () => change(!value),
      radius: BorderRadius.circular(8),
      dimWhenDisabled: 0.5,
      child: SizedBox(
        width: 44,
        height: 40,
        child: Center(
          child: SwitchTrack(value: value, large: large),
        ),
      ),
    );
  }
}

/// The look of an [AppSwitch] alone, for a row that is itself the switch, as a menu's is.
class SwitchTrack extends StatelessWidget {
  const SwitchTrack({super.key, required this.value, this.large = false});

  final bool value;

  /// The 38 by 22 track of a settings row, rather than the 34 by 20 of a file row.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final (width, height, knob) = large
        ? (38.0, 22.0, 18.0)
        : (34.0, 20.0, 16.0);
    return AnimatedContainer(
      duration: motion(context, const Duration(milliseconds: 150)),
      width: width,
      height: height,
      padding: const EdgeInsets.all(2),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: value ? t.accent : t.off,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Container(
        width: knob,
        height: knob,
        decoration: const BoxDecoration(
          color: Color(0xFFFFFFFF),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}

/// The block that blinks at the end of an answer while it streams. Still when the system asks
/// for reduced motion.
class Caret extends StatefulWidget {
  const Caret({super.key});

  @override
  State<Caret> createState() => _CaretState();
}

class _CaretState extends State<Caret> with SingleTickerProviderStateMixin {
  late final _blink = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _blink.stop();
    } else if (!_blink.isAnimating) {
      _blink.repeat();
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _blink,
        builder: (context, child) =>
            Opacity(opacity: _blink.value < 0.5 ? 1 : 0, child: child),
        child: Container(width: 7, height: 16, color: t.accent),
      ),
    );
  }
}
