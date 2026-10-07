import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

const _body =
    'M319.8 648.01 A39.82 39.82 0 0 1 317.01 652.6 A72.92 72.92 0 1 1 227.39 545.15 L347.72 491.9 A5.58 5.58 0 0 0 347.64 481.66 A158.64 158.64 0 0 0 159.12 732.15 A7.93 7.93 0 0 1 158.13 743.31 L125.96 770.33 A5.55 5.55 0 0 0 129.47 780.15 L272.84 780.2 A158.65 158.65 0 0 0 410.34 700.75 L510.96 526.54 A11.63 11.63 0 0 1 513.1 524.04 A5.63 5.63 0 0 0 514.11 522.42 A106.97 106.97 0 0 1 518.5 513.47 L623.01 332.45 A53.87 53.87 0 0 1 723.83 358.96 L723.83 565.97 A109.42 109.42 0 0 1 520.04 621.42 A5.55 5.55 0 0 0 510.75 621.86 L460.43 709.02 A5.55 5.55 0 0 0 461.24 715.69 A214.14 214.14 0 0 0 828.57 566.18 L828.57 374.58 A15.84 15.84 0 0 1 832.68 363.89 L870.55 322.09 A5.55 5.55 0 0 0 869.91 313.99 L767.79 234.04 A158.63 158.63 0 0 0 532.62 279.47 L319.8 648.01 Z';
const _breast =
    'M828.54 406.47 L768.83 406.47 L723.83 484.42 L723.83 563.57 A109.42 109.42 0 0 1 613.52 675.48 L557.53 772.46 A214.1 214.1 0 0 0 828.54 566.06 L828.54 406.47 Z';
const _eye =
    'M676.99 377.91 A26.96 26.96 0 1 0 676.54 377.89 L676.99 377.91 Z M689.36 332.16 A8.72 8.72 0 1 0 689.5 332.19 L689.36 332.16 Z';

const _breastColor = Color(0xFFF2853D);

final _paths = (
  body: parseSvgPathData(_body),
  breast: parseSvgPathData(_breast),
  eye: parseSvgPathData(_eye)..fillType = PathFillType.evenOdd,
);

/// The app's robin mark, drawn in [color] with an orange breast, on the 1024 unit box the
/// design draws it on.
class RobinMark extends StatelessWidget {
  const RobinMark({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _RobinPainter(color));
}

class _RobinPainter extends CustomPainter {
  _RobinPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 1024, size.height / 1024);
    final ink = Paint()..color = color;
    canvas.drawPath(_paths.body, ink);
    canvas.drawPath(_paths.breast, Paint()..color = _breastColor);
    canvas.drawPath(_paths.eye, ink);
  }

  @override
  bool shouldRepaint(_RobinPainter old) => old.color != color;
}
