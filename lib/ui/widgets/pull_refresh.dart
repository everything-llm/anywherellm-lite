import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../icons.dart';
import '../tokens.dart';

/// [child], a scroll view from the newest item up ([ScrollView.reverse]), with a pull down past
/// its oldest end calling [onRefresh]: a pull of [reach] or more, let go, refreshes. A refresh
/// icon follows the pull at the top and turns while [refreshing], when a pull does nothing.
/// With the platform's animations off ([MediaQuery.disableAnimationsOf]) the icon stays still,
/// shown while it refreshes, since House UI removes spin under reduced motion.
///
/// [child]'s physics must let it overscroll its oldest end even when it is too short to scroll,
/// as [AlwaysScrollableScrollPhysics] does on a platform that clamps.
class PullRefresh extends StatefulWidget {
  const PullRefresh({
    super.key,
    required this.onRefresh,
    required this.refreshing,
    required this.child,
  });

  final VoidCallback? onRefresh;
  final bool refreshing;
  final Widget child;

  /// How far the pull goes before letting go refreshes.
  static const reach = 80.0;

  @override
  State<PullRefresh> createState() => _PullRefreshState();
}

class _PullRefreshState extends State<PullRefresh>
    with SingleTickerProviderStateMixin {
  /// How far past the oldest end the pull has gone.
  final _pull = ValueNotifier<double>(0);
  late final _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// Whether the platform asks for no animation, read where the context allows it.
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    _spin();
  }

  @override
  void didUpdateWidget(PullRefresh old) {
    super.didUpdateWidget(old);
    _spin();
  }

  void _spin() {
    final spins = widget.refreshing && !_still;
    if (spins && !_turn.isAnimating) {
      _turn.repeat();
    } else if (!spins && _turn.isAnimating) {
      _turn.stop();
    }
  }

  @override
  void dispose() {
    _pull.dispose();
    _turn.dispose();
    super.dispose();
  }

  bool _scrolled(ScrollNotification note) {
    if (note.depth != 0) return false;
    switch (note) {
      // The list is reversed: past its oldest end is past its largest offset.
      case OverscrollNotification(:final overscroll, dragDetails: _?)
          when overscroll > 0 && note.metrics.extentAfter == 0:
        _pull.value += overscroll;
      case ScrollUpdateNotification(:final scrollDelta?, dragDetails: _?)
          when _pull.value > 0:
        // Scrolling back towards the newest takes the pull back first.
        _pull.value = math.max(0, _pull.value + scrollDelta);
      case ScrollEndNotification():
        if (_pull.value >= PullRefresh.reach && !widget.refreshing) {
          widget.onRefresh?.call();
        }
        _pull.value = 0;
      default:
        break;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return NotificationListener<ScrollNotification>(
      onNotification: widget.onRefresh == null ? null : _scrolled,
      child: Stack(
        children: [
          widget.child,
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: ValueListenableBuilder(
                valueListenable: _pull,
                builder: (context, pull, _) {
                  final shown = widget.refreshing
                      ? 1.0
                      : (pull / PullRefresh.reach).clamp(0.0, 1.0);
                  if (shown == 0) return const SizedBox.shrink();
                  return Center(
                    child: Opacity(
                      opacity: shown,
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.tile,
                          shape: BoxShape.circle,
                          border: Border.all(color: t.line),
                        ),
                        child: RotationTransition(
                          turns: _still
                              ? const AlwaysStoppedAnimation(0)
                              : widget.refreshing
                              ? _turn
                              : AlwaysStoppedAnimation(shown * 0.75),
                          child: AppIcon(
                            'refresh',
                            size: IconSize.xs,
                            color: shown >= 1 ? t.accent : t.muted,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
