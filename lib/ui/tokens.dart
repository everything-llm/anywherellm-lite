import 'package:flutter/material.dart';

import 'oklch.dart';

/// The colour tokens, light and dark.
@immutable
class Tokens extends ThemeExtension<Tokens> {
  const Tokens({
    required this.bg,
    required this.side,
    required this.panel,
    required this.panel2,
    required this.line,
    required this.line2,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.accent,
    required this.accentbg,
    required this.onaccent,
    required this.hover,
    required this.sel,
    required this.okfg,
    required this.okbg,
    required this.warnfg,
    required this.warnbg,
    required this.badfg,
    required this.badbg,
    required this.badln,
    required this.code,
    required this.fade,
    required this.scrim,
    required this.shadow,
  });

  final Color bg;
  final Color side;
  final Color panel;
  final Color panel2;
  final Color line;
  final Color line2;
  final Color ink;
  final Color ink2;
  final Color muted;
  final Color accent;
  final Color accentbg;
  final Color onaccent;
  final Color hover;
  final Color sel;
  final Color okfg;
  final Color okbg;
  final Color warnfg;
  final Color warnbg;
  final Color badfg;
  final Color badbg;
  final Color badln;
  final Color code;
  final Color fade;
  final Color scrim;
  final Color shadow;

  static final light = Tokens(
    bg: oklch(0.985, 0.006, 85),
    side: oklch(0.962, 0.01, 85),
    panel: oklch(1, 0, 0),
    panel2: oklch(0.99, 0.004, 85),
    line: oklch(0.9, 0.01, 85),
    line2: oklch(0.93, 0.01, 85),
    ink: oklch(0.24, 0.02, 60),
    ink2: oklch(0.38, 0.02, 60),
    muted: oklch(0.5, 0.02, 70),
    accent: oklch(0.45, 0.09, 165),
    accentbg: oklch(0.955, 0.02, 165),
    onaccent: oklch(1, 0, 0),
    hover: oklch(0.925, 0.012, 85),
    sel: oklch(0.92, 0.014, 85),
    okfg: oklch(0.38, 0.09, 150),
    okbg: oklch(0.94, 0.04, 150),
    warnfg: oklch(0.45, 0.12, 55),
    warnbg: oklch(0.95, 0.035, 70),
    badfg: oklch(0.45, 0.16, 25),
    badbg: oklch(0.96, 0.03, 25),
    badln: oklch(0.8, 0.09, 25),
    code: oklch(0.965, 0.008, 85),
    fade: oklch(0.62, 0.015, 80),
    scrim: oklch(0.2, 0.02, 60, 0.4),
    shadow: oklch(0.3, 0.02, 60, 0.12),
  );

  static final dark = Tokens(
    bg: oklch(0.2, 0.008, 60),
    side: oklch(0.18, 0.008, 60),
    panel: oklch(0.24, 0.008, 60),
    panel2: oklch(0.22, 0.008, 60),
    line: oklch(0.34, 0.01, 60),
    line2: oklch(0.29, 0.01, 60),
    ink: oklch(0.93, 0.008, 85),
    ink2: oklch(0.8, 0.01, 85),
    muted: oklch(0.7, 0.012, 80),
    accent: oklch(0.72, 0.12, 165),
    accentbg: oklch(0.3, 0.04, 165),
    onaccent: oklch(0.2, 0.01, 60),
    hover: oklch(0.27, 0.01, 60),
    sel: oklch(0.3, 0.012, 60),
    okfg: oklch(0.8, 0.1, 150),
    okbg: oklch(0.3, 0.05, 150),
    warnfg: oklch(0.82, 0.1, 65),
    warnbg: oklch(0.32, 0.05, 60),
    badfg: oklch(0.82, 0.11, 25),
    badbg: oklch(0.32, 0.06, 25),
    badln: oklch(0.5, 0.1, 25),
    code: oklch(0.22, 0.008, 60),
    fade: oklch(0.6, 0.01, 80),
    scrim: oklch(0.1, 0.01, 60, 0.6),
    shadow: oklch(0, 0, 0, 0.3),
  );

  static Tokens of(BuildContext context) =>
      Theme.of(context).extension<Tokens>()!;

  /// The theme does not animate between light and dark, so this only picks one.
  @override
  Tokens lerp(Tokens? other, double t) =>
      t < 0.5 || other == null ? this : other;

  @override
  Tokens copyWith() => this;
}
