import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../state/turn.dart';
import '../tokens.dart';
import '../type.dart';
import 'model_picker.dart';

/// What an answer waits on until its first words, as the Lite prototype draws it: a pulsing dot,
/// the step in plain words, and past 10 s the seconds since the question was sent. The step is
/// the agent's latest status line, or else the model being asked. The caret takes over once
/// words arrive.
class WaitLine extends StatefulWidget {
  const WaitLine(this.turn, {super.key});

  final Turn turn;

  /// How long the line waits before it counts the seconds.
  static const countFrom = Duration(seconds: 10);

  @override
  State<WaitLine> createState() => _WaitLineState();
}

class _WaitLineState extends State<WaitLine> {
  // Redraws each second, for the count.
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final style = Type.sans(13, color: t.muted, height: 1.4);
    final step =
        widget.turn.status ??
        'Asking ${knownWorkspaceModel(AppScope.of(context)) ?? 'the model'}…';
    final waited = clock.now().difference(widget.turn.asked ?? clock.now());
    return ConstrainedBox(
      // The height of a line of the answer, so its first words take the line's place.
      constraints: const BoxConstraints(minHeight: 26),
      child: Row(
        children: [
          const _Pulse(),
          const SizedBox(width: 6),
          Flexible(
            child: Semantics(
              liveRegion: true,
              child: Text(
                step,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ),
          if (waited >= WaitLine.countFrom)
            ExcludeSemantics(
              child: Text(
                ' · ${waited.inSeconds} s',
                style: style.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// An accent dot that fades and shrinks a little and back, every 1.6 s. Still when the system
/// asks for reduced motion.
class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  late final _eased = CurvedAnimation(parent: _beat, curve: Curves.easeInOut);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _beat
        ..stop()
        ..value = 0;
    } else if (!_beat.isAnimating) {
      unawaited(_beat.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _eased.dispose();
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _eased,
        builder: (context, child) => Opacity(
          opacity: 1 - 0.65 * _eased.value,
          child: Transform.scale(scale: 1 - 0.2 * _eased.value, child: child),
        ),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
