import 'package:flutter/material.dart';

import '../tokens.dart';
import '../type.dart';
import 'basics.dart';
import 'tappable.dart';
import 'rise.dart';

/// What an [AppBadge] says: a success or a warning, with House UI's icon for it; the accent, as
/// a count; or [plain], a state that is no status, such as Saved before a test.
enum BadgeKind { ok, warn, accent, plain }

/// A status tag or a count: its words at 13 on the status's soft fill. A status's words are in
/// ink beside its icon in the status's colour, so the colour never says it alone.
class AppBadge extends StatelessWidget {
  const AppBadge(this.text, {super.key, required this.kind});

  final String text;
  final BadgeKind kind;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final (fg, bg, status) = switch (kind) {
      BadgeKind.ok => (t.ink, t.successSoft, Status.success),
      BadgeKind.warn => (t.ink, t.warningSoft, Status.warning),
      BadgeKind.accent => (t.accent, t.accentSoft, null),
      BadgeKind.plain => (t.ink, t.sunken, null),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: StatusWord(text, status: status, style: Type.note(fg)),
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
      child: SizedBox(
        width: 52,
        height: Tappable.touchSide,
        child: Center(
          child: SwitchTrack(value: value, enabled: change != null),
        ),
      ),
    );
  }
}

/// The look of an [AppSwitch] alone, for a row that is itself the switch. Disabled
/// ([enabled] false) it stays opaque: a sunken track inside a line, its knob muted, which still
/// shows on or off by where it sits.
class SwitchTrack extends StatelessWidget {
  const SwitchTrack({super.key, required this.value, this.enabled = true});

  final bool value;
  final bool enabled;

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
        color: !enabled
            ? t.sunken
            : value
            ? t.accent
            : t.lineStrong,
        border: enabled ? null : Border.all(color: t.line),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Container(
        width: knob,
        height: knob,
        decoration: BoxDecoration(
          color: enabled ? t.tile : t.muted,
          shape: BoxShape.circle,
        ),
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
