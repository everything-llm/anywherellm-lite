import 'package:everything/core/prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips through its JSON', () {
    const prefs = Prefs(
      groundedOnly: false,
      switchedOff: {
        'q3': [
          OffDoc(path: 'custom-documents/a.json', title: 'a.md', words: 9),
        ],
      },
    );
    final back = Prefs.decode(prefs.encode());
    expect(back.groundedOnly, isFalse);
    final doc = back.offIn('q3').single;
    expect(
      (doc.path, doc.title, doc.words),
      ('custom-documents/a.json', 'a.md', 9),
    );
  });

  test('text that is not its JSON reads as the defaults', () {
    for (final text in ['', 'nope', '[]', '{"switchedOff": 3}']) {
      final prefs = Prefs.decode(text);
      expect(prefs.groundedOnly, isTrue, reason: text);
      expect(prefs.switchedOff, isEmpty, reason: text);
    }
  });

  test('entries it cannot read are skipped', () {
    final prefs = Prefs.decode(
      '{"switchedOff": {"w": [{"path": ""}, 7, {"path": "f/x.json"}]}}',
    );
    expect(prefs.offIn('w').single.title, 'f/x.json');
  });

  test('withOff replaces one workspace and drops it when empty', () {
    const doc = OffDoc(path: 'p', title: 't');
    final prefs = const Prefs().withOff('a', [doc]).withOff('b', [doc]);
    expect(prefs.switchedOff.keys, ['a', 'b']);
    expect(prefs.withOff('a', []).switchedOff.keys, ['b']);
  });
}
