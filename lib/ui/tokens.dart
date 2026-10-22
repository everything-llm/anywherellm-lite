import 'package:flutter/material.dart';

/// House UI's colour roles in its indigo scheme, with its shadows, in the light and dark themes
/// and the increased-contrast theme of each, as `exports/colors-native.json` gives them.
@immutable
class Tokens extends ThemeExtension<Tokens> {
  const Tokens({
    required this.ground,
    required this.sunken,
    required this.tile,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.scrim,
    required this.tileEdge,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.shadowInk,
    required this.tileShadow,
    required this.raisedShadow,
    required this.sheetShadow,
    required this.glow,
  });

  /// The page.
  final Color ground;

  /// Tracks, wells, empty bars, a row's lead icon, and a control's hover.
  final Color sunken;

  /// What holds content on the [ground].
  final Color tile;

  /// A decorative divider.
  final Color line;

  /// The edge of any control that needs one: a field, a secondary button, a chip, a switch.
  final Color lineStrong;

  /// Text, and secondary text smaller than the body.
  final Color ink;

  /// Secondary text at the body's size or larger, and a field's placeholder.
  final Color muted;

  /// The primary action, links, focus, and what is selected or current.
  final Color accent;

  /// The fill of a selected row, chip or segment, and of the person's own messages.
  final Color accentSoft;

  /// Text and icons on an [accent] fill.
  final Color onAccent;

  /// The one see-through layer, behind a sheet.
  final Color scrim;

  /// A tile's edge: none in the light and dark themes, solid in the increased-contrast ones.
  final Color tileEdge;

  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;

  /// The colour of a soft shadow drawn by hand, where a list of shadows does not fit.
  final Color shadowInk;

  /// What a tile floats on; none in the increased-contrast themes.
  final List<BoxShadow> tileShadow;

  /// What lifts a hero tile, a popover or a dragged item.
  final List<BoxShadow> raisedShadow;

  /// Above a bottom sheet.
  final List<BoxShadow> sheetShadow;

  /// Under the one primary action on a screen.
  final List<BoxShadow> glow;

  static const light = Tokens(
    shadowInk: Color(0x2430385A),
    ground: Color(0xFFEFF2FB),
    sunken: Color(0xFFE5E9F5),
    tile: Color(0xFFFDFDFF),
    line: Color(0xFFDADEE8),
    lineStrong: Color(0xFF7F8390),
    ink: Color(0xFF1C2130),
    muted: Color(0xFF535766),
    accent: Color(0xFF4758D5),
    accentSoft: Color(0xFFDEE5FE),
    onAccent: Color(0xFFFFFFFF),
    scrim: Color(0x6630385A),
    tileEdge: Color(0x00000000),
    success: Color(0xFF0C746B),
    successSoft: Color(0xFFCBF6EF),
    warning: Color(0xFF95590A),
    warningSoft: Color(0xFFFEE6D0),
    danger: Color(0xFF920810),
    dangerSoft: Color(0xFFFEE4E1),
    tileShadow: [
      BoxShadow(
        offset: Offset(0, 1),
        blurRadius: 2,
        spreadRadius: 0,
        color: Color(0x1430385A),
      ),
      BoxShadow(
        offset: Offset(0, 4),
        blurRadius: 8,
        spreadRadius: 0,
        color: Color(0x1430385A),
      ),
      BoxShadow(
        offset: Offset(0, 12),
        blurRadius: 24,
        spreadRadius: 0,
        color: Color(0x1430385A),
      ),
    ],
    raisedShadow: [
      BoxShadow(
        offset: Offset(0, 1),
        blurRadius: 2,
        spreadRadius: 0,
        color: Color(0x0F30385A),
      ),
      BoxShadow(
        offset: Offset(0, 4),
        blurRadius: 8,
        spreadRadius: 0,
        color: Color(0x1230385A),
      ),
      BoxShadow(
        offset: Offset(0, 12),
        blurRadius: 24,
        spreadRadius: -4,
        color: Color(0x1430385A),
      ),
      BoxShadow(
        offset: Offset(0, 24),
        blurRadius: 48,
        spreadRadius: -12,
        color: Color(0x1430385A),
      ),
    ],
    sheetShadow: [
      BoxShadow(
        offset: Offset(0, -4),
        blurRadius: 12,
        spreadRadius: 0,
        color: Color(0x0D30385A),
      ),
      BoxShadow(
        offset: Offset(0, -12),
        blurRadius: 32,
        spreadRadius: -8,
        color: Color(0x1230385A),
      ),
    ],
    glow: [
      BoxShadow(
        offset: Offset(0, 8),
        blurRadius: 24,
        spreadRadius: -4,
        color: Color(0x594758D5),
      ),
    ],
  );

  static const dark = Tokens(
    shadowInk: Color(0x66000002),
    ground: Color(0xFF11131A),
    sunken: Color(0xFF0B0D13),
    tile: Color(0xFF23262F),
    line: Color(0xFF393D49),
    lineStrong: Color(0xFF6D717D),
    ink: Color(0xFFE9EBF2),
    muted: Color(0xFFB3B7C5),
    accent: Color(0xFF859DFC),
    accentSoft: Color(0xFF2D3657),
    onAccent: Color(0xFF101428),
    scrim: Color(0x99000000),
    tileEdge: Color(0x00000000),
    success: Color(0xFF1EA79A),
    successSoft: Color(0xFF09332E),
    warning: Color(0xFFF3A759),
    warningSoft: Color(0xFF3B2612),
    danger: Color(0xFFF36358),
    dangerSoft: Color(0xFF3F221F),
    tileShadow: [
      BoxShadow(
        offset: Offset(0, 1),
        blurRadius: 2,
        spreadRadius: 0,
        color: Color(0x66000002),
      ),
      BoxShadow(
        offset: Offset(0, 4),
        blurRadius: 12,
        spreadRadius: 0,
        color: Color(0x4C000002),
      ),
    ],
    raisedShadow: [
      BoxShadow(
        offset: Offset(0, 2),
        blurRadius: 6,
        spreadRadius: 0,
        color: Color(0x66000002),
      ),
      BoxShadow(
        offset: Offset(0, 12),
        blurRadius: 32,
        spreadRadius: -8,
        color: Color(0x99000002),
      ),
    ],
    sheetShadow: [
      BoxShadow(
        offset: Offset(0, -12),
        blurRadius: 40,
        spreadRadius: -8,
        color: Color(0x99000002),
      ),
    ],
    glow: [
      BoxShadow(
        offset: Offset(0, 8),
        blurRadius: 24,
        spreadRadius: -4,
        color: Color(0x4C859DFC),
      ),
    ],
  );

  static const lightHc = Tokens(
    shadowInk: Color(0x00000000),
    ground: Color(0xFFF5F7FC),
    sunken: Color(0xFFE8EBF3),
    tile: Color(0xFFFFFFFF),
    line: Color(0xFF9B9EA8),
    lineStrong: Color(0xFF656875),
    ink: Color(0xFF0A0D16),
    muted: Color(0xFF323540),
    accent: Color(0xFF313AB4),
    accentSoft: Color(0xFFE0E7FE),
    onAccent: Color(0xFFFFFFFF),
    scrim: Color(0x9911131A),
    tileEdge: Color(0xFF656875),
    success: Color(0xFF06564F),
    successSoft: Color(0xFFCEF9F2),
    warning: Color(0xFF704105),
    warningSoft: Color(0xFFFFEBD8),
    danger: Color(0xFF680408),
    dangerSoft: Color(0xFFFFE9E6),
    tileShadow: [],
    raisedShadow: [],
    sheetShadow: [],
    glow: [],
  );

  static const darkHc = Tokens(
    shadowInk: Color(0x00000000),
    ground: Color(0xFF050609),
    sunken: Color(0xFF020204),
    tile: Color(0xFF121419),
    line: Color(0xFF515561),
    lineStrong: Color(0xFF7B7F8B),
    ink: Color(0xFFF9FAFD),
    muted: Color(0xFFCED1D9),
    accent: Color(0xFF9AAEFD),
    accentSoft: Color(0xFF1C2444),
    onAccent: Color(0xFF010210),
    scrim: Color(0xCC000000),
    tileEdge: Color(0xFF7B7F8B),
    success: Color(0xFF6AE1D3),
    successSoft: Color(0xFF012824),
    warning: Color(0xFFFEC186),
    warningSoft: Color(0xFF301D08),
    danger: Color(0xFFFD8C80),
    dangerSoft: Color(0xFF341916),
    tileShadow: [],
    raisedShadow: [],
    sheetShadow: [],
    glow: [],
  );

  /// The tokens for [brightness], the increased-contrast ones when [more] contrast is asked for.
  static Tokens forTheme(Brightness brightness, {bool more = false}) =>
      switch ((brightness, more)) {
        (Brightness.light, false) => light,
        (Brightness.dark, false) => dark,
        (Brightness.light, true) => lightHc,
        (Brightness.dark, true) => darkHc,
      };

  static Tokens of(BuildContext context) =>
      Theme.of(context).extension<Tokens>()!;

  /// The theme does not animate between light and dark, so this only picks one.
  @override
  Tokens lerp(Tokens? other, double t) =>
      t < 0.5 || other == null ? this : other;

  @override
  Tokens copyWith() => this;
}
