import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:anywherellm/ui/oklch.dart';
import 'package:anywherellm/ui/tokens.dart';

/// Each channel within [slack] of the expected 0..255 values.
Matcher near(int r, int g, int b, {int slack = 2}) => predicate<Color>((c) {
  int ch(double v) => (v * 255).round();
  return (ch(c.r) - r).abs() <= slack &&
      (ch(c.g) - g).abs() <= slack &&
      (ch(c.b) - b).abs() <= slack;
}, 'is within $slack of rgb($r, $g, $b)');

void main() {
  test('white and black', () {
    expect(oklch(1, 0, 0), near(255, 255, 255, slack: 0));
    expect(oklch(0, 0, 0), near(0, 0, 0, slack: 0));
  });

  test('a mid grey is gamma encoded', () {
    expect(oklch(0.5, 0, 0), near(99, 99, 99, slack: 1));
  });

  test('the sRGB primaries', () {
    expect(oklch(0.62796, 0.25768, 29.23), near(255, 0, 0));
    expect(oklch(0.86644, 0.29483, 142.5), near(0, 255, 0));
    expect(oklch(0.45201, 0.31321, 264.05), near(0, 0, 255));
  });

  test('a colour outside the gamut is pulled in, not wrapped', () {
    final c = oklch(0.7, 0.4, 150);
    for (final v in [c.r, c.g, c.b]) {
      expect(v, inInclusiveRange(0, 1));
    }
    // Still green: the hue survives the chroma reduction.
    expect(c.g, greaterThan(c.r));
    expect(c.g, greaterThan(c.b));
  });

  test('alpha is carried', () {
    expect(oklch(0.2, 0.02, 60, 0.4).a, closeTo(0.4, 0.005));
    expect(oklch(0.2, 0.02, 60).a, 1);
  });

  test('the accent is darker in light mode than in dark mode', () {
    expect(
      Tokens.dark.accent.computeLuminance(),
      greaterThan(Tokens.light.accent.computeLuminance()),
    );
  });

  test('text on its surfaces reads at 4.5:1 or more in both themes', () {
    double ratio(Color a, Color b) {
      final [lo, hi] = [a.computeLuminance(), b.computeLuminance()]..sort();
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final t in [Tokens.light, Tokens.dark]) {
      for (final (text, ground) in [
        (t.ink, t.bg),
        (t.muted, t.bg),
        (t.muted, t.panel2),
        (t.accent, t.bg),
        (t.accentfg, t.accentbg),
        (t.onaccent, t.accent),
      ]) {
        expect(ratio(text, ground), greaterThanOrEqualTo(4.5));
      }
    }
  });

  test('light and dark disagree on the page background', () {
    expect(Tokens.light.bg.g, greaterThan(0.9));
    expect(Tokens.dark.bg.g, lessThan(0.2));
  });

  test('every token is opaque except the scrim and the shadow', () {
    final t = Tokens.light;
    for (final c in [t.bg, t.side, t.panel, t.ink, t.accent, t.line]) {
      expect(c.a, 1);
    }
    expect(t.scrim.a, lessThan(1));
    expect(t.shadow.a, lessThan(1));
  });
}
