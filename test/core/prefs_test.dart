import 'package:anywherellm/core/prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips through its JSON', () {
    const prefs = Prefs(
      switchedOff: {
        'q3': [
          OffDoc(path: 'custom-documents/a.json', title: 'a.md', words: 9),
        ],
      },
    );
    final back = Prefs.decode(prefs.encode());
    final doc = back.offIn('q3').single;
    expect(
      (doc.path, doc.title, doc.words),
      ('custom-documents/a.json', 'a.md', 9),
    );
  });

  test('text that is not its JSON reads as the defaults', () {
    for (final text in ['', 'nope', '[]', '{"switchedOff": 3}']) {
      final prefs = Prefs.decode(text);
      expect(prefs.switchedOff, isEmpty, reason: text);
    }
  });

  test('an old file with the answers switch still loads', () {
    final prefs = Prefs.decode(
      '{"groundedOnly": true, "switchedOff": {"w": [{"path": "f/x.json"}]}}',
    );
    expect(prefs.offIn('w').single.path, 'f/x.json');
    expect(prefs.encode(), isNot(contains('groundedOnly')));
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

  test(
    'withoutDocs forgets the paths everywhere and drops emptied workspaces',
    () {
      const a = OffDoc(path: 'f/a.json', title: 'a');
      const b = OffDoc(path: 'f/b.json', title: 'b');
      final prefs = const Prefs().withOff('w', [a, b]).withOff('v', [a]);
      final next = prefs.withoutDocs({'f/a.json', 'f/c.json'});
      expect(next.switchedOff.keys, ['w']);
      expect(next.offIn('w').single.path, 'f/b.json');
    },
  );

  test('the order, theme and text size round-trip', () {
    final prefs = const Prefs()
        .withOrder(['b', 'a'])
        .withTheme(ThemePref.dark)
        .withTextSize(TextSize.large);
    final back = Prefs.decode(prefs.encode());
    expect(back.workspaceOrder, ['b', 'a']);
    expect(back.theme, ThemePref.dark);
    expect(back.textSize, TextSize.large);
  });

  test('an unknown theme or size reads as the default', () {
    final prefs = Prefs.decode(
      '{"theme": "neon", "textSize": 3, "workspaceOrder": ["a", 4, "b"]}',
    );
    expect(prefs.theme, ThemePref.system);
    expect(prefs.textSize, TextSize.normal);
    expect(prefs.workspaceOrder, ['a', 'b']);
  });

  test('inOrder puts the arranged ones first and keeps the rest in place', () {
    final prefs = const Prefs().withOrder(['c', 'a']);
    expect(prefs.inOrder(['a', 'b', 'c', 'd'], (s) => s), ['c', 'a', 'b', 'd']);
    expect(const Prefs().inOrder(['x', 'y'], (s) => s), ['x', 'y']);
  });

  test('arranging keeps the slugs it does not name, as another server\'s', () {
    final prefs = const Prefs(workspaceOrder: ['x', 'a', 'y'])
        .withOrder(['b', 'a']);
    expect(prefs.workspaceOrder, ['b', 'a', 'x', 'y']);
  });

  test('a renamed workspace keeps its place', () {
    final prefs = const Prefs(workspaceOrder: ['a', 'b', 'c']);
    expect(prefs.withRenamedWorkspace('b', 'z').workspaceOrder, [
      'a',
      'z',
      'c',
    ]);
    expect(prefs.withRenamedWorkspace('b', 'c').workspaceOrder, ['a', 'c']);
  });

  test('switching a document off keeps the other prefs', () {
    final prefs = const Prefs()
        .withTheme(ThemePref.light)
        .withOrder(['a'])
        .withOff('a', const [OffDoc(path: 'f/x.json', title: 'x')]);
    expect(prefs.theme, ThemePref.light);
    expect(prefs.workspaceOrder, ['a']);
    expect(prefs.withoutWorkspace('a').workspaceOrder, isEmpty);
  });
}
