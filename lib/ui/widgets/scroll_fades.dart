import 'package:flutter/material.dart';

import '../tokens.dart';

/// [child], with a short fade of [color] over its top edge once it has scrolled down and over its
/// bottom edge while more lies below, so content that runs out of view is not cut off hard. It
/// listens to the vertical scroll views inside [child]; the fades take no touches.
class ScrollFades extends StatefulWidget {
  const ScrollFades({super.key, required this.child, this.color});

  final Widget child;

  /// The ground the fades blend into; [Tokens.bg] when null.
  final Color? color;

  @override
  State<ScrollFades> createState() => _ScrollFadesState();
}

class _ScrollFadesState extends State<ScrollFades> {
  static const _height = 16.0;

  bool _top = false;
  bool _bottom = false;

  /// Follows [m], the metrics of the scroll view [depth] views down; only the outermost, if
  /// vertical, counts. Never handles the notification.
  bool _update(ScrollMetrics m, int depth) {
    if (depth != 0 || m.axis != Axis.vertical) return false;
    // In a reversed list the visual top is where the list continues.
    final reversed = m.axisDirection == AxisDirection.up;
    final top = (reversed ? m.extentAfter : m.extentBefore) > 1;
    final bottom = (reversed ? m.extentBefore : m.extentAfter) > 1;
    if (top != _top || bottom != _bottom) {
      // A notification can arrive while the tree is building.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _top = top;
            _bottom = bottom;
          });
        }
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Tokens.of(context).bg;
    Widget fade({required bool on, required bool top}) => Align(
      alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: on ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: _height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: [color, color.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      ),
    );
    // The metrics notification is sent as a list is laid out, so a list that fits or grows is
    // heard as well as one that scrolls.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _update(n.metrics, n.depth),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _update(n.metrics, n.depth),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            Positioned.fill(
              child: Stack(
                children: [
                  fade(on: _top, top: true),
                  fade(on: _bottom, top: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
