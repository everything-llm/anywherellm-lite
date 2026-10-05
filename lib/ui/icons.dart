import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

/// The icon paths, drawn as strokes on a 24 unit box.
const _paths = {
  'chat': 'M4 5h16v11H9l-5 4z',
  'settings': 'M4 7h9 M17 7h3 M4 17h3 M11 17h9 M13 7a2 2 0 1 0 4 0 2 2 0 0 0-4 0z M7 17a2 2 0 1 0 4 0 2 2 0 0 0-4 0z',
};

/// The small icons, drawn on a 16 unit box.
const _small = {
  'plus': 'M8 3v10M3 8h10',
  'pencil': 'M10.5 2.5l3 3L6 13H3v-3z',
  'trash': 'M3.5 4.5h9M6.5 4.5V3h3v1.5M4.5 4.5l.6 8h5.8l.6-8',
  'close': 'M3.5 3.5l9 9M12.5 3.5l-9 9',
  'doc': 'M4 1.8h5l3.2 3.2v9.2H4z M9 1.8V5h3.2',
  'send': 'M8 13V3M3.5 7.5 8 3l4.5 4.5',
  'hamburger': 'M2 4h12M2 8h12M2 12h12',
};

final _parsed = <String, Path>{};

Path _path(String name) => _parsed.putIfAbsent(
  name,
  () => parseSvgPathData(_paths[name] ?? _small[name]!),
);

/// The side of the box [name] is drawn on.
double _box(String name) => _small.containsKey(name) ? 16 : 24;

/// Icon sizes in logical pixels.
enum IconSize {
  xs(14),
  small(16),
  sm(15),
  normal(18);

  const IconSize(this.px);
  final double px;
}

class NilsIcon extends StatelessWidget {
  const NilsIcon(
    this.name, {
    super.key,
    this.size = IconSize.normal,
    this.color,
  });

  final String name;
  final IconSize size;

  /// Defaults to the surrounding [IconTheme] colour, which buttons and rows set.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    assert(
      _paths.containsKey(name) || _small.containsKey(name),
      'no icon named $name',
    );
    final icon = SizedBox.square(
      dimension: size.px,
      child: CustomPaint(
        painter: _IconPainter(
          _path(name),
          _box(name),
          color ?? IconTheme.of(context).color ?? const Color(0xFF000000),
        ),
      ),
    );
    return ExcludeSemantics(child: icon);
  }
}

class _IconPainter extends CustomPainter {
  const _IconPainter(this.path, this.box, this.color);

  final Path path;
  final double box;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / box;
    canvas.drawPath(
      path.transform(
        (Matrix4.identity()..scaleByDouble(scale, scale, 1, 1)).storage,
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = (box == 16 ? 1.6 : 1.7) * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.path != path || old.box != box || old.color != color;
}
