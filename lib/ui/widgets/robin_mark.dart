import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

// The bird with an angular tail and no spike, from the logo study "AnywhereLLM Ribbon Trim",
// in its own units; [_place] puts it on the 1024 unit box.
const _body =
    'M 507,715 L 441,599 V 562 L 481,492 H 629 L 600.5,542 H 510 L 491,575 V 585 L 536,665 H 588 L 759,365 C 787,316 823,282 867,282 C 899,282 925,294 952,314 L 1045,375 L 1007,417 V 450 H 956 L 917,510 V 424 C 917,391 898,368 869,368 C 847,368 830,380 816,404 L 641,715 Z';
const _belly =
    'M 734.3,587.2 C 759.3,606.5 798.0,623.2 825.0,621.9 C 867.0,618.1 906.0,561.5 917.0,510.0 L 956.0,450.0 L 1007.0,450.0 L 1007.0,500.0 C 1007.0,614.2 916.0,703.0 831.0,703.0 C 786.0,703.0 721.8,682.4 689.8,654.1 Z';
const _breast =
    'M 956.0,450.0 L 1007.0,450.0 L 1007.0,500.0 C 1007.0,614.2 916.0,703.0 831.0,703.0 C 817.0,703.0 804.0,701.7 791.0,697.9 L 825.0,621.9 C 867.0,618.1 906.0,561.5 917.0,510.0 Z';

/// The bird's units on the 1024 unit box: centred, at 1.25562 of its size.
final _place =
    (Matrix4.identity()
          ..translateByDouble(512, 512, 0, 1)
          ..scaleByDouble(1.25562, 1.25562, 1, 1)
          ..translateByDouble(-747.03, -513.06, 0, 1))
        .storage;

const _breastColor = Color(0xFFF2853D);

/// The launcher icon's tile, which the bird is drawn on in [iconInk].
const iconGround = Color(0xFF4B5DC3);

/// The launcher icon's bird.
const iconInk = Color(0xFFFFFFFF);

final _paths = (
  body: (parseSvgPathData(
    _body,
  )..addPath(parseSvgPathData(_belly), Offset.zero)).transform(_place),
  breast: parseSvgPathData(_breast).transform(_place),
  // The eye is a ring: the pupil shows what the bird is drawn on.
  eye:
      (Path()
            ..fillType = PathFillType.evenOdd
            ..addOval(
              Rect.fromCircle(center: const Offset(875, 408), radius: 22),
            )
            ..addOval(
              Rect.fromCircle(center: const Offset(882, 401), radius: 7.5),
            ))
          .transform(_place),
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
