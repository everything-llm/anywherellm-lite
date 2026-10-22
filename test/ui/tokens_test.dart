import 'dart:ui';

import 'package:anywherellm/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

double ratio(Color a, Color b) {
  final [lo, hi] = [a.computeLuminance(), b.computeLuminance()]..sort();
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const themes = {
    'light': (Tokens.light, 4.5),
    'dark': (Tokens.dark, 4.5),
    'light-hc': (Tokens.lightHc, 7.0),
    'dark-hc': (Tokens.darkHc, 7.0),
  };

  for (final MapEntry(key: name, value: (t, floor)) in themes.entries) {
    test('text reads at $floor:1 or more on its grounds in $name', () {
      for (final (text, ground) in [
        (t.ink, t.ground),
        (t.ink, t.tile),
        (t.ink, t.sunken),
        (t.muted, t.ground),
        (t.muted, t.tile),
        (t.accent, t.tile),
        (t.accent, t.accentSoft),
        (t.ink, t.accentSoft),
        (t.onAccent, t.accent),
        (t.danger, t.tile),
        (t.success, t.successSoft),
        (t.danger, t.dangerSoft),
      ]) {
        expect(ratio(text, ground), greaterThanOrEqualTo(floor));
      }
    });

    test('a control edge stands 3:1 off its ground in $name', () {
      expect(ratio(t.lineStrong, t.tile), greaterThanOrEqualTo(3));
      expect(ratio(t.lineStrong, t.ground), greaterThanOrEqualTo(3));
    });
  }

  test(
    'only the increased-contrast themes draw a tile edge, and no shadow',
    () {
      expect(Tokens.light.tileEdge.a, 0);
      expect(Tokens.dark.tileEdge.a, 0);
      for (final t in [Tokens.lightHc, Tokens.darkHc]) {
        expect(t.tileEdge.a, 1);
        expect(t.tileShadow, isEmpty);
        expect(t.glow, isEmpty);
      }
    },
  );

  test('every role is opaque except the scrim and the shadow', () {
    for (final t in [Tokens.light, Tokens.dark]) {
      for (final c in [t.ground, t.sunken, t.tile, t.ink, t.accent, t.line]) {
        expect(c.a, 1);
      }
      expect(t.scrim.a, lessThan(1));
      expect(t.shadowInk.a, lessThan(1));
    }
  });
}
