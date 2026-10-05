import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

/// The icon paths, drawn as strokes on a 24 unit box.
const _paths = {
  'book': 'M5 4h11a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3V4z M5 17a3 3 0 0 1 3-3h11',
  'tool': 'M14.5 6.5a4 4 0 0 0-5 5L4 17l3 3 5.5-5.5a4 4 0 0 0 5-5l-2.5 2.5-2-.5-.5-2z',
  'chevron': 'M9 6l6 6-6 6',
  'menu': 'M4 6h16 M4 12h16 M4 18h16',
  'file': 'M6 3h8l5 5v13H6z M14 3v5h5',
  'folder': 'M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
  'search': 'M17.5 11a6.5 6.5 0 0 1-13 0 6.5 6.5 0 0 1 13 0z M16 16l4.5 4.5',
};

final _parsed = <String, Path>{};

Path _path(String name) =>
    _parsed.putIfAbsent(name, () => parseSvgPathData(_paths[name]!));

/// Icon sizes: `.ico` 18, `.sm` 15 and `.big` 22.
enum IconSize {
  sm(15),
  normal(18),
  big(22);

  const IconSize(this.px);
  final double px;
}

class NilsIcon extends StatelessWidget {
  const NilsIcon(
    this.name, {
    super.key,
    this.size = IconSize.normal,
    this.color,
    this.rotated = false,
  });

  final String name;
  final IconSize size;

  /// Defaults to the surrounding [IconTheme] colour, which buttons and rows set.
  final Color? color;

  /// A quarter turn clockwise. The chevrons rotate when a section opens.
  final bool rotated;

  @override
  Widget build(BuildContext context) {
    assert(_paths.containsKey(name), 'no icon named $name');
    final icon = SizedBox.square(
      dimension: size.px,
      child: CustomPaint(
        painter: _IconPainter(
          _path(name),
          color ?? IconTheme.of(context).color ?? const Color(0xFF000000),
        ),
      ),
    );
    return ExcludeSemantics(
      child: rotated ? RotatedBox(quarterTurns: 1, child: icon) : icon,
    );
  }
}

class _IconPainter extends CustomPainter {
  const _IconPainter(this.path, this.color);

  final Path path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.drawPath(
      path.transform(
        (Matrix4.identity()..scaleByDouble(scale, scale, 1, 1)).storage,
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7 * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.path != path || old.color != color;
}
