import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

/// The icon paths, the design canvas's own, drawn as strokes on a 16 unit box.
const _paths = {
  'server': 'M2.5 3h11v4h-11z M2.5 9h11v4h-11z M5 5h.01 M5 11h.01',
  'chat': 'M3 3.5h10v7.5H7.5L4.5 13.5V11H3z',
  'brush': 'M13.5 2.5 6.5 9.5 M6.5 9.5c-1.5-.5-3 .5-3 2 0 .8-.5 1.3-1 1.5 2 .8 4.5 0 4.5-2.3z',
  'settings': 'M2 5h8M13 5h1M2 11h1M6 11h8M10 3.5v3M4 9.5v3',
  'search': 'M7 12A5 5 0 1 0 7 2a5 5 0 0 0 0 10z M11 11l3 3',
  'check': 'M3.5 8.5l3 3 6-7',
  'pin': 'M6 2.5h4l-.5 4 2 2.5h-7l2-2.5z M8 9v4.5',
  'more': 'M4 8h.01M8 8h.01M12 8h.01',
  'menu': 'M2 4h12M2 8h12M2 12h12',
  'mic': 'M8 2a2 2 0 0 0-2 2v3.5a2 2 0 0 0 4 0V4a2 2 0 0 0-2-2z M3.8 7.5a4.2 4.2 0 0 0 8.4 0 M8 11.7V14',
  'plus': 'M8 3v10M3 8h10',
  'pencil': 'M3 13l.8-3.3 7-7 2.5 2.5-7 7z',
  'trash': 'M3.5 4.5h9 M6 4.5V3h4v1.5 M4.5 4.5l.5 8.5h6l.5-8.5',
  'close': 'M4 4l8 8M12 4l-8 8',
  'doc': 'M4 2h5l3 3v9H4z M9 2v3h3',
  'folder': 'M2 4.5h4l1.5 1.5H14v6.5H2z',
  'send': 'M8 13V3M3.5 7.5 8 3l4.5 4.5',
  'chevron': 'M6 4l4 4-4 4',
  'down': 'M4 6l4 4 4-4',
  'back': 'M10 3.5 5.5 8l4.5 4.5',
  'refresh': 'M13 8a5 5 0 1 1-1.5-3.5 M13 2.5v3h-3',
  'copy': 'M5.5 5.5h7v7h-7z M3.5 10.5v-7h7',
  'attach': 'M13 7.5l-5.2 5.2a3 3 0 0 1-4.3-4.3L9 2.9a2 2 0 0 1 2.9 2.9L6.4 11.3a1 1 0 0 1-1.4-1.4L10 4.9',
  'speaker': 'M2.5 6h2.5l3.5-3v10l-3.5-3H2.5z M11 5.5a3.5 3.5 0 0 1 0 5 M12.8 3.8a6 6 0 0 1 0 8.4',
  'stop': 'M4.5 4.5h7v7h-7z',
  'download': 'M8 2.5v8 M4.5 7.5 8 11l3.5-3.5 M3 13.5h10',
  'external': 'M9.5 2.5h4v4 M13.5 2.5 7.5 8.5 M11.5 9.5v4h-9v-9h4',
  'share': 'M8 10V2.5 M5 5.5 8 2.5l3 3 M5.5 7.5h-2v6h9v-6h-2',
  'memory': 'M6 13.5h4 M6.2 11.5h3.6 M8 1.8a4.2 4.2 0 0 0-2.4 7.6c.4.3.6.8.6 1.3v.8h3.6v-.8c0-.5.2-1 .6-1.3A4.2 4.2 0 0 0 8 1.8z',
  'clock': 'M8 14A6 6 0 1 0 8 2a6 6 0 0 0 0 12z M8 5v3l2 1.5',
  'code': 'M5.5 3C4 3 4 4 4 5v1.5C4 7.5 3 8 2.5 8 3 8 4 8.5 4 9.5V11c0 1 0 2 1.5 2 M10.5 3C12 3 12 4 12 5v1.5c0 1 1 1.5 1.5 1.5-.5 0-1.5.5-1.5 1.5V11c0 1 0 2-1.5 2',
  'grid': 'M3 3h4v4H3z M9 3h4v4H9z M3 9h4v4H3z M9 9h4v4H9z',
  'link': 'M7 9a3 3 0 0 0 4 0l2-2a3 3 0 0 0-4-4l-1 1 M9 7a3 3 0 0 0-4 0l-2 2a3 3 0 0 0 4 4l1-1',
  'thumb-up': 'M5 7v6.5H2.5V7z M5 7l2.5-4.5a1.3 1.3 0 0 1 2.4.8L9.5 6h3.2a1.2 1.2 0 0 1 1.2 1.4l-.9 5a1.2 1.2 0 0 1-1.2 1H5',
  'thumb-down': 'M5 9V2.5H2.5V9z M5 9l2.5 4.5a1.3 1.3 0 0 0 2.4-.8L9.5 10h3.2a1.2 1.2 0 0 0 1.2-1.4l-.9-5a1.2 1.2 0 0 0-1.2-1H5',
};

final _parsed = <String, Path>{};

Path _path(String name) =>
    _parsed.putIfAbsent(name, () => parseSvgPathData(_paths[name]!));

/// Icon sizes in logical pixels.
enum IconSize {
  tiny(12),
  xs(14),
  small(16),
  sm(15),
  normal(18),

  /// A tab's icon in the bar at the home's foot.
  medium(20),

  /// A row's icon in a sheet's grouped card.
  row(22),

  /// A row's icon in a grouped card.
  large(24);

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
    assert(_paths.containsKey(name), 'no icon named $name');
    final icon = SizedBox.square(
      dimension: size.px,
      child: CustomPaint(
        painter: _IconPainter(
          _path(name),
          // The dots of More are drawn as round caps, wider than a line.
          name == 'more' ? 2.4 : 1.6,
          color ?? IconTheme.of(context).color ?? const Color(0xFF000000),
        ),
      ),
    );
    return ExcludeSemantics(child: icon);
  }
}

class _IconPainter extends CustomPainter {
  const _IconPainter(this.path, this.stroke, this.color);

  final Path path;

  /// The stroke's width in the box's units.
  final double stroke;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 16;
    canvas.drawPath(
      path.transform(
        (Matrix4.identity()..scaleByDouble(scale, scale, 1, 1)).storage,
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.path != path || old.stroke != stroke || old.color != color;
}
