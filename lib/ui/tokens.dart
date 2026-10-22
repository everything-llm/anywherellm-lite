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
    required this.accentfg,
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

  /// Text and icons in the accent drawn on [accentbg], where [accent] itself is too faint.
  final Color accentfg;
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
    bg: oklch(0.962, 0.012, 272),
    side: oklch(0.938, 0.014, 272),
    panel: oklch(0.995, 0.002, 272),
    panel2: oklch(0.98, 0.006, 272),
    line: oklch(0.89, 0.014, 272),
    line2: oklch(0.925, 0.012, 272),
    edge: oklch(0.58, 0.02, 272),
    ink: oklch(0.25, 0.03, 272),
    ink2: oklch(0.38, 0.028, 272),
    muted: oklch(0.46, 0.025, 272),
    accent: oklch(0.54, 0.22, 272),
    accentbg: oklch(0.908, 0.044, 270),
    accentfg: oklch(0.45, 0.209, 272),
    onaccent: oklch(1, 0, 0),
    hover: oklch(0.925, 0.016, 272),
    sel: oklch(0.917, 0.04, 270),
    okfg: oklch(0.468, 0.083, 184),
    okbg: oklch(0.945, 0.04, 185),
    warnfg: oklch(0.529, 0.119, 64),
    warnbg: oklch(0.944, 0.039, 66),
    badfg: oklch(0.42, 0.17, 27),
    badbg: oklch(0.95, 0.025, 27),
    badln: oklch(0.8, 0.09, 27),
    scrim: oklch(0.25, 0.03, 272, 0.4),
    shadow: oklch(0.35, 0.06, 272, 0.14),
    bubble: oklch(0.917, 0.04, 270),
    off: oklch(0.84, 0.012, 272),
    chosen: oklch(0.995, 0.002, 272),
    knob: oklch(0.995, 0.002, 272),
  );

  static final dark = Tokens(
    bg: oklch(0.19, 0.014, 272),
    side: oklch(0.165, 0.014, 272),
    panel: oklch(0.27, 0.018, 272),
    panel2: oklch(0.23, 0.016, 272),
    line: oklch(0.4, 0.022, 272),
    line2: oklch(0.33, 0.02, 272),
    edge: oklch(0.6, 0.022, 272),
    ink: oklch(0.94, 0.01, 272),
    ink2: oklch(0.82, 0.014, 272),
    muted: oklch(0.72, 0.02, 272),
    accent: oklch(0.62, 0.18, 272),
    accentbg: oklch(0.34, 0.09, 272),
    accentfg: oklch(0.834, 0.082, 269),
    onaccent: oklch(0.2, 0.05, 272),
    hover: oklch(0.31, 0.02, 272),
    sel: oklch(0.331, 0.063, 272),
    okfg: oklch(0.801, 0.12, 185),
    okbg: oklch(0.32, 0.05, 185),
    warnfg: oklch(0.83, 0.12, 65),
    warnbg: oklch(0.319, 0.05, 65),
    badfg: oklch(0.7, 0.119, 27),
    badbg: oklch(0.33, 0.06, 27),
    badln: oklch(0.5, 0.1, 27),
    scrim: oklch(0.1, 0.02, 272, 0.6),
    shadow: oklch(0.05, 0.02, 272, 0.4),
    bubble: oklch(0.319, 0.064, 271),
    off: oklch(0.42, 0.02, 272),
    chosen: oklch(0.4, 0.03, 272),
    knob: oklch(0.82, 0.014, 272),
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
