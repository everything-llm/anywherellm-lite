import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

import '../tokens.dart';
import '../type.dart';
import '../widgets/rise.dart';
import '../widgets/tappable.dart';
import 'rows.dart';

/// The pictures of the walk-throughs, drawn on a 300 by 180 unit box as the Lite prototype
/// draws them, each with the [name] shown under it.
enum GuideArt {
  hero(
    'Phone and server',
    'A phone joined to an AnythingLLM server by an address and a key',
  ),
  key(
    'Key page',
    'AnythingLLM web page: Settings, Developer API, Generate New API Key',
  ),
  kit(
    'Settings, expanded',
    'The toolkit beside AnythingLLM adds a Memory row to this app\'s Settings',
  ),
  pick(
    'Installer page',
    'The installer\'s page lists each AnythingLLM it found, with Add the toolkit',
  ),
  pair(
    'Pairing code',
    'The installer\'s page shows a code, and the phone scans it',
  );

  const GuideArt(this.name, this.label);

  /// The figure's name, under it.
  final String name;

  /// What a screen reader hears for the picture.
  final String label;
}

/// Each AnythingLLM the installer's page offers in [GuideArt.pick], with what its readout
/// says when it is picked.
const _found = [
  (
    'AnythingLLM Desktop',
    'the app on this computer',
    'AnythingLLM Desktop: its storage folder on this computer.',
  ),
  (
    'anythingllm',
    'a podman container',
    'anythingllm: a podman container. The toolkit goes into the storage it mounts.',
  ),
];

/// [art] as a component, in a card as wide as the page: the picture, at most [maxHeight]
/// tall, which grows in as it shows; for [GuideArt.pick] a readout of the AnythingLLM tapped;
/// and the figure's name under a rule.
class GuideFigure extends StatefulWidget {
  const GuideFigure(this.art, {super.key, required this.maxHeight});

  final GuideArt art;
  final double maxHeight;

  @override
  State<GuideFigure> createState() => _GuideFigureState();
}

class _GuideFigureState extends State<GuideFigure> {
  /// Which of [_found] the installer's page has picked.
  int _picked = 0;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final art = widget.art;
    final picture = AspectRatio(
      aspectRatio: 300 / 180,
      // Its own layer, so the screen's rise moves it without painting it again.
      child: RepaintBoundary(
        child: CustomPaint(painter: _FigurePainter(art, t, _picked)),
      ),
    );
    return Container(
      decoration: cardDecoration(t),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
            child: Center(
              child: _Grow(
                child: art == GuideArt.pick
                    ? _picker(picture)
                    : Semantics(image: true, label: art.label, child: picture),
              ),
            ),
          ),
          if (art == GuideArt.pick)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _found[_picked].$3,
                  style: Type.sans(13, color: t.ink2, height: 1.4),
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.line2)),
            ),
            child: Text(
              art.name,
              style: Type.sans(12.5, weight: FontWeight.w500, color: t.muted),
            ),
          ),
        ],
      ),
    );
  }

  /// [picture] with a tap target over each AnythingLLM the installer's page lists.
  Widget _picker(Widget picture) => Semantics(
    label: widget.art.label,
    container: true,
    child: Stack(
      children: [
        picture,
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, box) {
              final unit = box.maxWidth / 300;
              return Stack(
                children: [
                  for (final (n, (name, about, _)) in _found.indexed)
                    Positioned(
                      left: 24 * unit,
                      top: (60 + n * 40) * unit,
                      width: 252 * unit,
                      height: 34 * unit,
                      child: Tappable(
                        label: '$name, $about',
                        selected: n == _picked,
                        onTap: () => setState(() => _picked = n),
                        child: const SizedBox.expand(),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

/// [child] growing in from a little smaller as it shows, unless the system asks for reduced
/// motion.
class _Grow extends StatelessWidget {
  const _Grow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.94, end: 1),
    duration: motion(context, const Duration(milliseconds: 450)),
    curve: Curves.easeOutBack,
    child: child,
    builder: (context, scale, child) =>
        Transform.scale(scale: scale, child: child),
  );
}

class _FigurePainter extends CustomPainter {
  _FigurePainter(this.art, this.t, this.picked);

  final GuideArt art;
  final Tokens t;
  final int picked;

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
          ..window(14, 16, 272, 148)
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
      case GuideArt.kit:
        pen
          ..server(14, 22)
          ..box(14, 134, 76, 28, 14, fill: t.accent)
          ..text(52, 152, 'Toolkit', _Ink.onAccent, centred: true)
          ..path('M98 92H128', faint: true, dashed: true)
          ..box(136, 14, 150, 152, 12, fill: t.panel, edge: true)
          ..text(150, 36, 'Settings', _Ink.name)
          ..text(150, 62, 'Connection', _Ink.note)
          ..path('M150 72h122', faint: true)
          ..text(150, 90, 'Appearance', _Ink.note)
          ..path('M150 100h122', faint: true)
          ..text(150, 118, 'Server', _Ink.note)
          ..box(144, 128, 134, 28, 8, fill: t.accentbg)
          ..text(154, 146, 'Memory', _Ink.name)
          ..text(268, 146, 'new', _Ink.note, end: true);
      case GuideArt.pick:
        pen
          ..window(14, 12, 272, 156, address: '127.0.0.1:8470')
          ..text(28, 52, 'Pick an AnythingLLM for the toolkit.', _Ink.name);
        for (final (n, (name, about, _)) in _found.indexed) {
          final y = 60.0 + n * 40;
          final on = n == picked;
          pen
            ..box(
              24,
              y,
              252,
              34,
              8,
              fill: on ? t.accentbg : t.panel,
              edge: true,
              edgeColor: on ? t.accent : t.line,
            )
            ..ring(38, y + 17, 5, strong: true);
          if (on) pen.dot(38, y + 17, 3);
          pen
            ..text(50, y + 14, name, _Ink.name)
            ..text(50, y + 27, about, _Ink.note);
        }
        pen
          ..box(24, 140, 110, 22, 8, fill: t.accent)
          ..text(79, 155, 'Add the toolkit', _Ink.onAccent, centred: true);
      case GuideArt.pair:
        pen
          ..window(14, 22, 156, 136)
          ..code(60, 50)
          ..text(92, 140, 'The code your phone scans', _Ink.note, centred: true)
          ..path('M176 92H216', faint: true, dashed: true)
          ..text(196, 84, 'scan', _Ink.note, centred: true)
          ..phone(222, 40);
    }
  }

  @override
  bool shouldRepaint(_FigurePainter old) =>
      old.art != art || old.t != t || old.picked != picked;
}

/// The kinds of words in a figure: a muted note, a name, words on the accent, and a key.
enum _Ink { note, name, onAccent, mono }

/// Draws a figure's marks in the box's units: lines in [Tokens.ink2], faint ones in
/// [Tokens.muted], fills in the accent.
class _Pen {
  _Pen(this.canvas, this.t);

  final Canvas canvas;
  final Tokens t;

  Paint _stroke({bool faint = false, Color? color}) => Paint()
    ..style = PaintingStyle.stroke
    ..color = color ?? (faint ? t.muted : t.ink2)
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

  /// A rounded box, filled with [fill], edged in [edgeColor], or [Tokens.ink2], with [edge].
  void box(
    double x,
    double y,
    double w,
    double h,
    double r, {
    Color? fill,
    bool edge = false,
    Color? edgeColor,
    bool dashed = false,
  }) {
    final shape = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, w, h),
      Radius.circular(r),
    );
    if (fill != null) canvas.drawRRect(shape, Paint()..color = fill);
    if (edge) {
      _draw(Path()..addRRect(shape), _stroke(color: edgeColor), dashed);
    }
  }

  /// A browser window: its frame, a bar with two dots, and the [address] in it.
  void window(double x, double y, double w, double h, {String? address}) {
    box(x, y, w, h, 10, fill: t.panel, edge: true);
    path('M$x ${y + 20}h$w', faint: true);
    ring(x + 12, y + 10, 3);
    ring(x + 22, y + 10, 3);
    if (address != null) text(x + 38, y + 13, address, _Ink.mono);
  }

  /// A faint rule, drawn as the prototype's two-unit outlined bar.
  void _bar(double x, double y, double w) =>
      canvas.drawRect(Rect.fromLTWH(x, y, w, 2), _stroke(faint: true));

  void ring(double x, double y, double r, {bool strong = false}) =>
      canvas.drawCircle(Offset(x, y), r, _stroke(faint: !strong));

  /// A dot in the accent.
  void dot(double x, double y, double r) => _dot(x, y, r, t.accent);

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

  /// A pairing code drawn on a 63 unit square from [x], [y]: three finder squares and a
  /// scatter of modules.
  void code(double x, double y) {
    for (final (a, b) in [(0.0, 0.0), (42.0, 0.0), (0.0, 42.0)]) {
      box(x + a, y + b, 21, 21, 2, fill: t.accent);
      box(x + a + 3, y + b + 3, 15, 15, 1, fill: t.panel);
      box(x + a + 6, y + b + 6, 9, 9, 1, fill: t.accent);
    }
    for (final (a, b) in const [
      (27.0, 3.0), (33.0, 9.0), (27.0, 21.0), (39.0, 27.0), (51.0, 27.0), //
      (27.0, 33.0), (45.0, 39.0), (57.0, 45.0), (33.0, 51.0), (45.0, 57.0),
      (27.0, 57.0), (57.0, 57.0), (3.0, 27.0), (15.0, 27.0), (9.0, 33.0),
    ]) {
      box(x + a, y + b, 6, 6, 0, fill: t.accent);
    }
  }

  /// [words] on the baseline at [y], starting at [x], centred on it, or ending at it.
  void text(
    double x,
    double y,
    String words,
    _Ink ink, {
    bool centred = false,
    bool end = false,
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
    final left = centred
        ? x - painter.width / 2
        : end
        ? x - painter.width
        : x;
    painter.paint(canvas, Offset(left, y - baseline));
    painter.dispose();
  }
}
