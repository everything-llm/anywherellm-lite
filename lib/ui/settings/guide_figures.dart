import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

import '../tokens.dart';
import '../type.dart';
import 'rows.dart';

/// The pictures of the guide to connecting, drawn on a 300 by 180 unit box as the Lite
/// prototype draws them.
enum GuideArt {
  hero('A phone joined to an AnythingLLM server by an address and a key'),
  key('AnythingLLM web page: Settings, Developer API, Generate New API Key'),
  safe('Plain http inside your network; https across the internet'),
  addOns('AnythingLLM with two optional add-ons beside it');

  const GuideArt(this.label);

  /// What a screen reader hears for the picture.
  final String label;
}

/// [art] in a card as wide as the page, at most [maxHeight] tall.
class GuideFigure extends StatelessWidget {
  const GuideFigure(this.art, {super.key, required this.maxHeight});

  final GuideArt art;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      image: true,
      label: art.label,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        padding: const EdgeInsets.all(6),
        decoration: cardDecoration(t),
        child: Center(
          child: AspectRatio(
            aspectRatio: 300 / 180,
            // Its own layer, so the screen's rise moves it without painting it again.
            child: RepaintBoundary(
              child: CustomPaint(painter: _FigurePainter(art, t)),
            ),
          ),
        ),
      ),
    );
  }
}

class _FigurePainter extends CustomPainter {
  _FigurePainter(this.art, this.t);

  final GuideArt art;
  final Tokens t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 300);
    final pen = _Pen(canvas, t);
    switch (art) {
      case GuideArt.hero:
        pen
          ..phone(30, 38)
          ..server(196, 40)
          ..path('M92 90H190', faint: true, dashed: true)
          ..key(128, 90)
          ..text(141, 118, 'address + key', _Ink.note, centred: true);
      case GuideArt.key:
        pen
          ..box(14, 16, 272, 148, 10, fill: t.panel, edge: true)
          ..path('M14 36h272', faint: true)
          ..ring(26, 26, 3)
          ..ring(36, 26, 3)
          ..text(26, 58, 'Settings', _Ink.note)
          ..box(20, 68, 78, 20, 6, fill: t.accentbg)
          ..text(26, 82, 'Developer API', _Ink.name)
          ..text(26, 106, 'Appearance', _Ink.note)
          ..text(26, 126, 'Agent skills', _Ink.note)
          ..path('M108 44v112', faint: true)
          ..box(122, 56, 148, 26, 8, fill: t.accent)
          ..text(196, 73, 'Generate New API Key', _Ink.onAccent, centred: true)
          ..box(122, 96, 148, 26, 8, edge: true)
          ..text(132, 113, 'ABC1D2E-F3GH…', _Ink.mono)
          ..key(140, 146)
          ..text(172, 149, 'copy it once', _Ink.note);
      case GuideArt.safe:
        pen
          ..phone(14, 38)
          ..server(210, 30)
          ..path('M70 58H88M192 58H210')
          ..box(88, 36, 104, 44, 22, fill: t.accentbg)
          ..text(140, 56, 'your network', _Ink.name, centred: true)
          ..text(140, 70, 'http is fine', _Ink.note, centred: true)
          ..path('M70 126H88M192 126H210', faint: true, dashed: true)
          ..box(88, 104, 104, 44, 22, fill: t.panel, edge: true)
          ..text(140, 124, 'the internet', _Ink.name, centred: true)
          ..text(140, 138, 'https only', _Ink.note, centred: true)
          ..box(180, 96, 16, 12, 2, fill: t.accent)
          ..path('M183 96v-4a5 5 0 0 1 10 0v4');
      case GuideArt.addOns:
        pen
          ..server(112, 8)
          ..box(18, 116, 100, 44, 10, edge: true, dashed: true)
          ..text(68, 136, 'Apps server', _Ink.name, centred: true)
          ..text(68, 150, 'Apps', _Ink.note, centred: true)
          ..box(182, 116, 100, 44, 10, edge: true, dashed: true)
          ..text(232, 136, 'Toolkit', _Ink.name, centred: true)
          ..text(232, 150, 'Memory · Upcoming', _Ink.note, centred: true)
          ..path('M120 112l-32 4M180 112l32 4', faint: true);
    }
  }

  @override
  bool shouldRepaint(_FigurePainter old) => old.art != art || old.t != t;
}

/// The kinds of words in a figure: a muted note, a name, words on the accent, and a key.
enum _Ink { note, name, onAccent, mono }

/// Draws a figure's marks in the box's units: lines in [Tokens.ink2], faint ones in
/// [Tokens.muted], fills in the accent.
class _Pen {
  _Pen(this.canvas, this.t);

  final Canvas canvas;
  final Tokens t;

  Paint _stroke({bool faint = false}) => Paint()
    ..style = PaintingStyle.stroke
    ..color = faint ? t.muted : t.ink2
    ..strokeWidth = faint ? 1.2 : 1.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _draw(Path path, Paint paint, bool dashed) => canvas.drawPath(
    dashed
        ? dashPath(path, dashArray: CircularIntervalList<double>([4, 3]))
        : path,
    paint,
  );

  void path(String data, {bool faint = false, bool dashed = false}) =>
      _draw(parseSvgPathData(data), _stroke(faint: faint), dashed);

  /// A rounded box, filled with [fill], edged in [Tokens.ink2] with [edge].
  void box(
    double x,
    double y,
    double w,
    double h,
    double r, {
    Color? fill,
    bool edge = false,
    bool dashed = false,
  }) {
    final shape = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, w, h),
      Radius.circular(r),
    );
    if (fill != null) canvas.drawRRect(shape, Paint()..color = fill);
    if (edge) _draw(Path()..addRRect(shape), _stroke(), dashed);
  }

  /// A faint rule, drawn as the prototype's two-unit outlined bar.
  void _bar(double x, double y, double w) =>
      canvas.drawRect(Rect.fromLTWH(x, y, w, 2), _stroke(faint: true));

  void ring(double x, double y, double r) =>
      canvas.drawCircle(Offset(x, y), r, _stroke(faint: true));

  void _dot(double x, double y, double r, Color color) =>
      canvas.drawCircle(Offset(x, y), r, Paint()..color = color);

  /// A phone with a heading and two lines on its screen.
  void phone(double x, double y) {
    box(x, y, 56, 104, 10, edge: true);
    box(x + 10, y + 16, 24, 5, 0, fill: t.accent);
    _bar(x + 10, y + 30, 36);
    _bar(x + 10, y + 40, 28);
  }

  /// A server named AnythingLLM: three lines and a light.
  void server(double x, double y) {
    box(x, y, 76, 78, 8, fill: t.panel, edge: true);
    for (final o in [18.0, 30.0, 42.0]) {
      _bar(x + 10, y + o, 56);
    }
    _dot(x + 62, y + 62, 4, t.accent);
    text(x + 38, y + 96, 'AnythingLLM', _Ink.name, centred: true);
  }

  /// A key whose ring is centred on [x], [y].
  void key(double x, double y) {
    _dot(x, y, 9, t.accent);
    _dot(x, y, 3.5, t.panel);
    box(x + 7, y - 2.5, 20, 5, 0, fill: t.accent);
    box(x + 21, y, 4, 7, 0, fill: t.accent);
  }

  /// [words] on the baseline at [y], starting at [x] or centred on it.
  void text(
    double x,
    double y,
    String words,
    _Ink ink, {
    bool centred = false,
  }) {
    final style = switch (ink) {
      _Ink.note => Type.sans(10, weight: FontWeight.w500, color: t.muted),
      _Ink.name => Type.sans(10, weight: FontWeight.w600, color: t.ink),
      _Ink.onAccent => Type.sans(
        10,
        weight: FontWeight.w600,
        color: t.onaccent,
      ),
      _Ink.mono => Type.mono(9, weight: FontWeight.w500, color: t.ink2),
    };
    final painter = TextPainter(
      text: TextSpan(text: words, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    painter.paint(
      canvas,
      Offset(centred ? x - painter.width / 2 : x, y - baseline),
    );
    painter.dispose();
  }
}
