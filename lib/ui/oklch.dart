import 'dart:math' as math;
import 'dart:ui';

/// A colour written as CSS writes it, `oklch(l c h / a)`, so the tokens in tokens.dart read
/// as the design's own values.
///
/// [l] is 0..1, [c] is chroma, [h] is the hue angle in degrees and [a] is opacity. A colour
/// outside the sRGB gamut keeps its lightness and hue and loses chroma until it fits, which is
/// what CSS Color 4 gamut mapping does.
Color oklch(double l, double c, double h, [double a = 1]) {
  var rgb = _linear(l, c, h);
  if (!_inGamut(rgb)) {
    var low = 0.0;
    var high = c;
    for (var i = 0; i < 24; i++) {
      final mid = (low + high) / 2;
      if (_inGamut(_linear(l, mid, h))) {
        low = mid;
      } else {
        high = mid;
      }
    }
    rgb = _linear(l, low, h);
  }
  int byte(double v) => (_encode(v.clamp(0.0, 1.0)) * 255).round();
  return Color.fromARGB(
    (a * 255).round(),
    byte(rgb[0]),
    byte(rgb[1]),
    byte(rgb[2]),
  );
}

List<double> _linear(double l, double c, double h) {
  final rad = h * math.pi / 180;
  final a = c * math.cos(rad);
  final b = c * math.sin(rad);
  final lp = math.pow(l + 0.3963377774 * a + 0.2158037573 * b, 3).toDouble();
  final mp = math.pow(l - 0.1055613458 * a - 0.0638541728 * b, 3).toDouble();
  final sp = math.pow(l - 0.0894841775 * a - 1.2914855480 * b, 3).toDouble();
  return [
    4.0767416621 * lp - 3.3077115913 * mp + 0.2309699292 * sp,
    -1.2684380046 * lp + 2.6097574011 * mp - 0.3413193965 * sp,
    -0.0041960863 * lp - 0.7034186147 * mp + 1.7076147010 * sp,
  ];
}

bool _inGamut(List<double> rgb) =>
    rgb.every((v) => v >= -0.0005 && v <= 1.0005);

double _encode(double v) => v <= 0.0031308
    ? 12.92 * v
    : 1.055 * math.pow(v, 1 / 2.4).toDouble() - 0.055;
