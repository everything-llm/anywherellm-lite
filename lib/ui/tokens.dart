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
    required this.edge,
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
    required this.scrim,
    required this.shadow,
    required this.bubble,
    required this.off,
    required this.chosen,
    required this.knob,
  });

  final Color bg;
  final Color side;
  final Color panel;
  final Color panel2;
  final Color line;
  final Color line2;

  /// A control's own outline, a text field's or an outlined button's: 3 to 1 against the page
  /// and the card behind it, where [line] is a rule, 1.3 to 1.
  final Color edge;
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
  final Color scrim;
  final Color shadow;

  /// The fill behind the person's own messages.
  final Color bubble;

  /// A switch that is off, and a send button with nothing to send.
  final Color off;

  /// The fill of the chosen segment of a segmented control: lighter than the [hover] track it
  /// sits in, in light and dark alike.
  final Color chosen;

  /// The knob of a switch that is off: light against [off] in light and dark alike.
  final Color knob;

  static final light = Tokens(
    bg: oklch(0.982, 0.008, 75),
    side: oklch(0.958, 0.013, 75),
    panel: oklch(0.995, 0.003, 75),
    panel2: oklch(0.989, 0.006, 75),
    line: oklch(0.895, 0.014, 75),
    line2: oklch(0.928, 0.012, 75),
    edge: oklch(0.62, 0.014, 75),
    ink: oklch(0.27, 0.025, 280),
    ink2: oklch(0.4, 0.025, 280),
    muted: oklch(0.5, 0.02, 280),
    accent: oklch(0.52, 0.16, 272),
    accentbg: oklch(0.94, 0.028, 272),
    onaccent: oklch(1, 0, 0),
    hover: oklch(0.925, 0.016, 75),
    sel: oklch(0.93, 0.028, 272),
    okfg: oklch(0.42, 0.08, 165),
    okbg: oklch(0.945, 0.04, 165),
    warnfg: oklch(0.45, 0.1, 70),
    warnbg: oklch(0.95, 0.045, 80),
    badfg: oklch(0.47, 0.16, 20),
    badbg: oklch(0.95, 0.025, 20),
    badln: oklch(0.8, 0.09, 20),
    scrim: oklch(0.25, 0.03, 280, 0.4),
    shadow: oklch(0.35, 0.04, 280, 0.14),
    bubble: oklch(0.945, 0.026, 272),
    off: oklch(0.84, 0.012, 75),
    chosen: oklch(0.995, 0.003, 75),
    knob: oklch(0.995, 0.003, 75),
  );

  static final dark = Tokens(
    bg: oklch(0.215, 0.018, 280),
    side: oklch(0.19, 0.018, 280),
    panel: oklch(0.26, 0.02, 280),
    panel2: oklch(0.235, 0.019, 280),
    line: oklch(0.36, 0.022, 280),
    line2: oklch(0.31, 0.02, 280),
    edge: oklch(0.55, 0.022, 280),
    ink: oklch(0.93, 0.01, 75),
    ink2: oklch(0.81, 0.014, 75),
    muted: oklch(0.78, 0.018, 280),
    accent: oklch(0.78, 0.1, 272),
    accentbg: oklch(0.33, 0.06, 272),
    onaccent: oklch(0.2, 0.03, 280),
    hover: oklch(0.29, 0.02, 280),
    sel: oklch(0.33, 0.045, 272),
    okfg: oklch(0.82, 0.1, 165),
    okbg: oklch(0.32, 0.05, 165),
    warnfg: oklch(0.84, 0.1, 80),
    warnbg: oklch(0.33, 0.05, 70),
    badfg: oklch(0.83, 0.085, 20),
    badbg: oklch(0.33, 0.06, 20),
    badln: oklch(0.5, 0.1, 20),
    scrim: oklch(0.1, 0.02, 280, 0.6),
    shadow: oklch(0, 0, 0, 0.35),
    bubble: oklch(0.31, 0.04, 272),
    off: oklch(0.42, 0.02, 280),
    chosen: oklch(0.4, 0.03, 280),
    knob: oklch(0.81, 0.014, 75),
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
