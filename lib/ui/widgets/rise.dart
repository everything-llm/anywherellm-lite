import 'dart:async';

import 'package:flutter/widgets.dart';

/// The `rise` animation: fade in while sliding up six pixels. It is skipped when
/// the system asks for reduced motion.
class Rise extends StatelessWidget {
  const Rise({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOut,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 6),
          child: child,
        ),
      ),
    );
  }
}

/// [duration], or none when the system asks for reduced motion.
Duration motion(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

/// A scroll view moved as [motion] allows: at once when the system asks for reduced motion, since
/// a scroll controller refuses to animate over no time.
extension MotionScroll on ScrollController {
  /// Scrolls to [offset] over [duration].
  void glideTo(
    BuildContext context,
    double offset,
    Duration duration, {
    Curve curve = Curves.easeOut,
  }) {
    final time = motion(context, duration);
    if (time == Duration.zero) return jumpTo(offset);
    unawaited(animateTo(offset, duration: time, curve: curve));
  }
}

/// A pager moved as [motion] allows, as [MotionScroll] moves a scroll view.
extension MotionPages on PageController {
  /// Turns to [page] over [duration].
  void turnTo(
    BuildContext context,
    int page,
    Duration duration, {
    Curve curve = Curves.easeOutCubic,
  }) {
    final time = motion(context, duration);
    if (time == Duration.zero) return jumpToPage(page);
    unawaited(animateToPage(page, duration: time, curve: curve));
  }
}
