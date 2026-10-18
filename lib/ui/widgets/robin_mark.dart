import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';

// The bird of the "AnywhereLLM Icon" artifact's variant C: an even line weight, an open wing
// gap and every straight edge on the 60 degree grid, in its own units; [_place] puts it on the
// 1024 unit box as that artifact's master tile does.
const _body =
    'M 766.9,365 C 794.9,316.5 823,282 867,282 C 899,282 925,294 952,314 L 1045,375 L 1007,417 V 450 H 956 L 917,510 V 424 C 917,391 898,368 869,368 C 847,368 830,380 816,404 L 636.4,715 L 564.9,715 L 508,715 L 441,599 L 441,562 L 481.4,492 L 635.9,492 L 600.1,554 L 517.2,554 L 503,578.6 L 503,582.4 L 543.8,653 L 600.6,653 Z';
const _belly =
    'M 736.8,589.1 C 761.9,607.6 798.9,623.2 825,621.9 C 867,618.1 906,561.5 917,510 L 956,450 L 1007,450 L 1007,500 C 1007,614.2 916,703 831,703 C 788.9,703 729.9,684.9 696.3,659.4 Z';
const _breast =
    'M 830.4,621.1 C 870.3,613.3 906.5,559.3 917,510 L 956,450 L 1007,450 L 1007,500 C 1007,614.2 916,703 831,703 C 817.4,703 801.9,701.1 786.2,697.7 Z';

/// The bird's units on the 1024 unit box, as the master tile places them: at 1.25562 of their
/// size, then shrunk to 0.985 about the middle and moved 14 right and 6 down.
final _place =
    (Matrix4.identity()
          ..translateByDouble(14, 6, 0, 1)
          ..translateByDouble(512, 512, 0, 1)
          ..scaleByDouble(0.985, 0.985, 1, 1)
          ..translateByDouble(-512, -512, 0, 1)
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
              Rect.fromCircle(center: const Offset(875, 408), radius: 27),
            )
            ..addOval(
              Rect.fromCircle(center: const Offset(884.3, 398.7), radius: 10),
            ))
          .transform(_place),
);

/// The app's robin mark, drawn in [color] with an orange breast, on the 1024 unit box the
/// design draws it on. With [breast] false it is one colour: the belly under the breast takes
/// [color].
class RobinMark extends StatelessWidget {
  const RobinMark({
    super.key,
    required this.size,
    required this.color,
    this.breast = true,
  });

  final double size;
  final Color color;
  final bool breast;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _RobinPainter(color, breast),
  );
}

class _RobinPainter extends CustomPainter {
  _RobinPainter(this.color, this.breast);

  final Color color;
  final bool breast;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 1024, size.height / 1024);
    final ink = Paint()..color = color;
    canvas.drawPath(_paths.body, ink);
    if (breast) {
      canvas.drawPath(_paths.breast, Paint()..color = _breastColor);
    }
    canvas.drawPath(_paths.eye, ink);
  }

  @override
  bool shouldRepaint(_RobinPainter old) =>
      old.color != color || old.breast != breast;
}
