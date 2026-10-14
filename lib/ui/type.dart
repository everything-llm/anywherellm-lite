import 'package:flutter/painting.dart';

/// Text styles for the two faces. Instrument Sans and JetBrains Mono are variable fonts, so
/// the weight is set on the `wght` axis as well as on the style. A line with no [height] given
/// is the face's own, as CSS's `normal` is, rather than the Material theme's; a line taller
/// than its text shares the extra evenly above and below it, as CSS does.
abstract final class Type {
  static const _sans = 'Instrument Sans';
  static const _mono = 'JetBrains Mono';

  /// Each face's own line, its ascent and descent over its em.
  static const _sansLine = 1.22;
  static const _monoLine = 1.32;

  static const _fallback = ['Noto Sans', 'DejaVu Sans', 'sans-serif'];
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
    height: height ?? _sansLine,
    leadingDistribution: TextLeadingDistribution.even,
    letterSpacing: letterSpacing,
  );

  /// The line height of a field of several lines, as the design canvas sets a text area.
  static const textAreaLine = 1.5;

  /// Text in a field of several lines at [size], in [color].
  static TextStyle textArea(double size, Color color) =>
      sans(size, color: color, height: textAreaLine);

  /// The size of what is said in a chat, before the person's Chat text size and the system's:
  /// Material's body large, with its line 1.6, which keeps the pitch the chat had at 15.5.
  static const chat = 16.0;

  /// A muted note at 13, as under a card or a sheet's title, in [color].
  static TextStyle note(Color color) => sans(13, color: color, height: 1.45);

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
    height: height ?? _monoLine,
    leadingDistribution: TextLeadingDistribution.even,
  );
}
