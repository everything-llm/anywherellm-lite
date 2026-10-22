import 'package:flutter/painting.dart';

/// House UI's type: running text in the platform's own face (Roboto on Android), Instrument Sans
/// for headlines and titles only, and JetBrains Mono for code, addresses, model names and IDs.
/// Each style has its own line height; a line taller than its text shares the extra evenly
/// above and below it, as CSS does. Instrument Sans and JetBrains Mono are variable fonts, so
/// the weight is set on the `wght` axis as well as on the style.
abstract final class Type {
  static const _sans = 'Roboto';
  static const _display = 'Instrument Sans';
  static const _mono = 'JetBrains Mono';

  static const _fallback = ['Noto Sans', 'DejaVu Sans', 'sans-serif'];
  static const _monoFallback = ['DejaVu Sans Mono', 'monospace'];

  /// One per screen, a claim with a verb: 32, display, 600.
  static TextStyle headline(Color color) =>
      display(32, color: color, height: 1.2, letterSpacing: -0.8);

  /// A tile's, sheet's or panel's title, and a section's heading: 20, display, 600.
  static TextStyle title(Color color) => display(20, color: color, height: 1.3);

  /// Running text, a row's title and subtitle, help text and meta lines: 16 at 400. Secondary
  /// text is this in muted.
  static TextStyle body(Color color, {FontWeight weight = FontWeight.w400}) =>
      sans(16, weight: weight, color: color, height: 1.5);

  /// Text inside a control: a button, chip, tab, segment or field label: 16 at 600.
  static TextStyle label(Color color) =>
      sans(16, weight: FontWeight.w600, color: color, height: 1.25);

  /// Metadata and glanceable labels: 13 at 500, always in ink.
  static TextStyle caption(
    Color color, {
    FontWeight weight = FontWeight.w500,
  }) => sans(13, weight: weight, color: color, height: 1.4);

  /// Code, paths, IDs and model names: 15, mono.
  static TextStyle code(Color color) => mono(15, color: color, height: 1.45);

  /// The platform face at [size].
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
    color: color,
    height: height,
    leadingDistribution: TextLeadingDistribution.even,
    letterSpacing: letterSpacing,
  );

  /// Instrument Sans at [size], for a headline, a title or a numeral.
  static TextStyle display(
    double size, {
    FontWeight weight = FontWeight.w600,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: _display,
    fontFamilyFallback: _fallback,
    fontSize: size,
    fontWeight: weight,
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
    color: color,
    height: height,
    leadingDistribution: TextLeadingDistribution.even,
    letterSpacing: letterSpacing,
  );

  /// The line height of a field of one line.
  static const fieldLine = 1.25;

  /// The line height of a field of several lines.
  static const textAreaLine = 1.5;

  /// Text in a field of several lines at [size], in [color].
  static TextStyle textArea(double size, Color color) =>
      sans(size, color: color, height: textAreaLine);

  /// The size of what is said in a chat, before the person's Chat text size and the system's.
  static const chat = 16.0;

  /// Metadata under a card or a sheet's title, in [color]: [caption] at 400.
  static TextStyle note(Color color) => caption(color, weight: FontWeight.w400);

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
    leadingDistribution: TextLeadingDistribution.even,
  );
}
