import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

/// The icon paths, drawn as strokes on a 24 unit box.
const _paths = {
  'chat': 'M4 5h16v11H9l-5 4z',
  'settings': 'M4 7h9 M17 7h3 M4 17h3 M11 17h9 M13 7a2 2 0 1 0 4 0 2 2 0 0 0-4 0z M7 17a2 2 0 1 0 4 0 2 2 0 0 0-4 0z',
};

/// The small icons, drawn on a 16 unit box.
const _small = {
  'search': 'M7 3a4 4 0 1 0 0 8 4 4 0 0 0 0-8z M10 10l3.5 3.5',
  'check': 'M3.5 8.5l3 3 6-7',
  'pin': 'M6 2.5h4 M7 2.5v4L4.5 9h7L9 6.5v-4 M8 9v4.5',
  'more': 'M3 8a1 1 0 1 0 2 0 1 1 0 0 0-2 0z M7 8a1 1 0 1 0 2 0 1 1 0 0 0-2 0z M11 8a1 1 0 1 0 2 0 1 1 0 0 0-2 0z',
  'unfold': 'M5 6.5l3-3 3 3 M5 9.5l3 3 3-3',
  'mic': 'M8 2a2 2 0 0 0-2 2v3.5a2 2 0 0 0 4 0V4a2 2 0 0 0-2-2z M3.8 7.5a4.2 4.2 0 0 0 8.4 0 M8 11.7V14',
  'plus': 'M8 3v10M3 8h10',
  'pencil': 'M10.5 2.5l3 3L6 13H3v-3z',
  'trash': 'M3.5 4.5h9M6.5 4.5V3h3v1.5M4.5 4.5l.6 8h5.8l.6-8',
  'close': 'M3.5 3.5l9 9M12.5 3.5l-9 9',
  'doc': 'M4 1.8h5l3.2 3.2v9.2H4z M9 1.8V5h3.2',
  'send': 'M8 13V3M3.5 7.5 8 3l4.5 4.5',
  'slash': 'M10.5 2.5l-5 11',
  'hamburger': 'M2 4h12M2 8h12M2 12h12',
  'folder': 'M2 4h4l1.5 1.5H14v7.5H2z',
  'chevron': 'M6 4l4 4-4 4',
  'down': 'M4 6l4 4 4-4',
  'back': 'M10 4 6 8l4 4',
  'lock': 'M4.5 7.5h7v6h-7z M6 7.5V5.5a2 2 0 0 1 4 0v2',
  'refresh': 'M13 8a5 5 0 1 1-1.5-3.5 M13 2.5v3h-3',
  'copy': 'M5.5 5.5h7v7h-7z M3.5 10.5v-7h7',
  'attach': 'M13 7.5l-5.2 5.2a3 3 0 0 1-4.3-4.3L9 2.9a2 2 0 0 1 2.9 2.9L6.4 11.3a1 1 0 0 1-1.4-1.4L10 4.9',
  'speaker': 'M2.5 6h2.5l3.5-3v10l-3.5-3H2.5z M11 5.5a3.5 3.5 0 0 1 0 5 M12.8 3.8a6 6 0 0 1 0 8.4',
  'stop': 'M4.5 4.5h7v7h-7z',
  'download': 'M8 2.5v8 M4.5 7 8 10.5 11.5 7 M3 13.5h10',
  'globe': 'M8 2a6 6 0 1 0 0 12A6 6 0 0 0 8 2z M2 8h12 M8 2c-2.2 2.2-2.2 9.8 0 12 M8 2c2.2 2.2 2.2 9.8 0 12',
  'external': 'M9.5 2.5h4v4 M13.5 2.5 7.5 8.5 M11.5 9.5v4h-9v-9h4',
  'share': 'M8 10V2.5 M5 5.5 8 2.5l3 3 M5.5 7.5h-2v6h9v-6h-2',
  'activity': 'M1.5 8h3l1.5-4 3 8 1.5-4h4',
  'memory': 'M6 13.5h4 M6.2 11.5h3.6 M8 1.8a4.2 4.2 0 0 0-2.4 7.6c.4.3.6.8.6 1.3v.8h3.6v-.8c0-.5.2-1 .6-1.3A4.2 4.2 0 0 0 8 1.8z',
  'clock': 'M8 2a6 6 0 1 0 0 12A6 6 0 0 0 8 2z M8 4.5V8l2.5 1.5',
  'grid': 'M3 3h4v4H3z M9 3h4v4H9z M3 9h4v4H3z M9 9h4v4H9z',
  'link': 'M7 9a2.5 2.5 0 0 0 3.5 0l2.3-2.3a2.5 2.5 0 0 0-3.5-3.5L8.5 4 M9 7a2.5 2.5 0 0 0-3.5 0L3.2 9.3a2.5 2.5 0 0 0 3.5 3.5l.8-.8',
  'thumb-up': 'M5 7v6.5H2.5V7z M5 7l2.5-4.5a1.3 1.3 0 0 1 2.4.8L9.5 6h3.2a1.2 1.2 0 0 1 1.2 1.4l-.9 5a1.2 1.2 0 0 1-1.2 1H5',
  'thumb-down': 'M5 9V2.5H2.5V9z M5 9l2.5 4.5a1.3 1.3 0 0 0 2.4-.8L9.5 10h3.2a1.2 1.2 0 0 0 1.2-1.4l-.9-5a1.2 1.2 0 0 0-1.2-1H5',
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
  tiny(12),
  xs(14),
  small(16),
  sm(15),
  normal(18);

  const IconSize(this.px);
  final double px;
}

class AppIcon extends StatelessWidget {
  const AppIcon(
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
