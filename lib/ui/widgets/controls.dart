import 'package:flutter/material.dart';

import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';
import 'rise.dart';

enum BadgeKind { ok, warn, accent }

/// A status tag or a count: its words at 13 on the status's soft fill.
class AppBadge extends StatelessWidget {
  const AppBadge(this.text, {super.key, required this.kind});

  final String text;
  final BadgeKind kind;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final (fg, bg) = switch (kind) {
      BadgeKind.ok => (t.success, t.successSoft),
      BadgeKind.warn => (t.warning, t.warningSoft),
      BadgeKind.accent => (t.accent, t.accentSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: Type.note(fg)),
    );
  }
}

/// An on and off switch: a [Tokens.lineStrong] track with a tile knob, the accent when on.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.tooltip,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// What a screen reader hears.
  final String label;
  final String? tooltip;

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
        width: 52,
        height: 44,
        child: Center(child: SwitchTrack(value: value)),
      ),
    );
  }
}

/// The look of an [AppSwitch] alone, for a row that is itself the switch.
class SwitchTrack extends StatelessWidget {
  const SwitchTrack({super.key, required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    const width = 38.0, height = 22.0, knob = 18.0;
    return AnimatedContainer(
      duration: motion(context, const Duration(milliseconds: 150)),
      width: width,
      height: height,
      padding: const EdgeInsets.all(2),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: value ? t.accent : t.lineStrong,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Container(
        width: knob,
        height: knob,
        decoration: BoxDecoration(color: t.tile, shape: BoxShape.circle),
      ),
    );
  }
}

/// The bar, 2 wide and 18 tall, that blinks at the end of an answer while it streams. Still when the system asks
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
        child: Container(width: 2, height: 18, color: t.accent),
      ),
    );
  }
}
