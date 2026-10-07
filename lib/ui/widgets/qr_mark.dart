import 'package:flutter/widgets.dart';
import 'package:qr/qr.dart';

/// [data] as a square QR code as wide as it is allowed: dark modules on a white quiet zone in either theme,
/// since many scanners cannot read a light-on-dark code. Screen readers hear [label], never
/// [data].
class QrMark extends StatelessWidget {
  const QrMark(this.data, {super.key, required this.label});

  final String data;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: label,
    excludeSemantics: true,
    child: AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(painter: _QrPainter(data)),
    ),
  );
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.data);

  final String data;

  /// The quiet zone on each side, in modules, as the QR standard asks.
  static const _quiet = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final image = QrImage(QrCode(payload: QrPayload.fromString(data)));
    final count = image.moduleCount;
    final module = size.width / (count + 2 * _quiet);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final dark = Path();
    for (var row = 0; row < count; row++) {
      for (var col = 0; col < count; col++) {
        if (!image.isDark(row, col)) continue;
        dark.addRect(
          Rect.fromLTWH(
            (col + _quiet) * module,
            (row + _quiet) * module,
            module,
            module,
          ),
        );
      }
    }
    // Filled as one path, so neighbouring modules show no hairline seams.
    canvas.drawPath(dark, Paint()..color = const Color(0xFF000000));
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
