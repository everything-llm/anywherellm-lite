import 'package:flutter/widgets.dart';

/// A dashed rounded border, drawn behind [child]. Flutter has none of its own.
class DashedBox extends StatelessWidget {
  const DashedBox({
    super.key,
    required this.color,
    required this.child,
    this.radius = 16,
    this.width = 1,
    this.dash = 5,
    this.gap = 4,
    this.fill,
    this.padding = EdgeInsets.zero,
  });

  final Color color;
  final Widget child;
  final double radius;
  final double width;
  final double dash;
  final double gap;
  final Color? fill;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedPainter(color, radius, width, dash, gap, fill),
    child: Padding(padding: padding, child: child),
  );
}

class _DashedPainter extends CustomPainter {
  const _DashedPainter(
    this.color,
    this.radius,
    this.width,
    this.dash,
    this.gap,
    this.fill,
  );

  final Color color;
  final double radius;
  final double width;
  final double dash;
  final double gap;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(width / 2),
      Radius.circular(radius),
    );
    if (fill != null) canvas.drawRRect(rect, Paint()..color = fill!);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final outline = Path()..addRRect(rect);
    for (final metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += dash + gap) {
        canvas.drawPath(
          metric.extractPath(at, (at + dash).clamp(0, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.width != width ||
      old.dash != dash ||
      old.gap != gap ||
      old.fill != fill;
}
