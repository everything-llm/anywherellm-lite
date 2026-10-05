import 'package:flutter/painting.dart';

/// Text styles for the three faces. Instrument Sans and JetBrains Mono are variable fonts, so
/// the weight is set on the `wght` axis as well as on the style.
abstract final class Type {
  static const _sans = 'Instrument Sans';
  static const _serif = 'Instrument Serif';
  static const _mono = 'JetBrains Mono';

  static const _fallback = ['Noto Sans', 'DejaVu Sans', 'sans-serif'];
  static const _serifFallback = ['Noto Serif', 'DejaVu Serif', 'serif'];
  static const _monoFallback = ['DejaVu Sans Mono', 'monospace'];

  static TextStyle sans(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: _sans,
    fontFamilyFallback: _fallback,
    fontSize: size,
    fontWeight: weight,
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );

  /// Headings and the brand. Instrument Serif has a single weight.
  static TextStyle serif(
    double size, {
    Color? color,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: _serif,
    fontFamilyFallback: _serifFallback,
    fontSize: size,
    fontWeight: FontWeight.w400,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );

  static TextStyle mono(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
  }) => TextStyle(
    fontFamily: _mono,
    fontFamilyFallback: _monoFallback,
    fontSize: size,
    fontWeight: weight,
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
    color: color,
    height: height,
  );
}
