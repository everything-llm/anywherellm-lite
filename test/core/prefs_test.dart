import 'package:anywherellm/core/prefs.dart';
import 'package:flutter_test/flutter_test.dart';

const _s = 'https://s:3001';
const _t = 'https://t:3001';

void main() {
  test('round-trips through its JSON', () {
    const prefs = Prefs(
      switchedOff: {
        '$_s q3': [
          OffDoc(path: 'custom-documents/a.json', title: 'a.md', words: 9),
        ],
      },
    );
    final back = Prefs.decode(prefs.encode());
    final doc = back.offIn(_s, 'q3').single;
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
    expect(prefs.adoptedBy(_s).offIn(_s, 'w').single.path, 'f/x.json');
    expect(prefs.encode(), isNot(contains('groundedOnly')));
  });

  test('entries it cannot read are skipped', () {
    final prefs = Prefs.decode(
      '{"switchedOff": {"w": [{"path": ""}, 7, {"path": "f/x.json"}]}}',
    );
    expect(prefs.adoptedBy(_s).offIn(_s, 'w').single.title, 'f/x.json');
  });

  test('withOff replaces one workspace and drops it when empty', () {
    const doc = OffDoc(path: 'p', title: 't');
    final prefs = const Prefs().withOff(_s, 'a', [doc]).withOff(_s, 'b', [doc]);
    expect(prefs.switchedOff.keys, ['$_s a', '$_s b']);
    expect(prefs.withOff(_s, 'a', []).switchedOff.keys, ['$_s b']);
  });

  test(
    'withoutDocs forgets the paths everywhere and drops emptied workspaces',
    () {
      const a = OffDoc(path: 'f/a.json', title: 'a');
      const b = OffDoc(path: 'f/b.json', title: 'b');
      final prefs = const Prefs()
          .withOff(_s, 'w', [a, b])
          .withOff(_s, 'v', [a])
          .withOff(_t, 'v', [a]);
      final next = prefs.withoutDocs(_s, {'f/a.json', 'f/c.json'});
      expect(next.switchedOff.keys, ['$_s w', '$_t v']);
      expect(next.offIn(_s, 'w').single.path, 'f/b.json');
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

  test('the chat switches round-trip, and one not set is its default', () {
    final prefs = const Prefs()
        .withSwitch(ChatSwitch.spellcheck, false)
        .withSwitch(ChatSwitch.readAnswers, true);
    final back = Prefs.decode(prefs.encode());
    expect(back.isOn(ChatSwitch.spellcheck), isFalse);
    expect(back.isOn(ChatSwitch.readAnswers), isTrue);
    expect(back.isOn(ChatSwitch.followAnswer), isTrue);
    expect(back.isOn(ChatSwitch.reasoningOpen), isFalse);
  });

  test('a chat switch it cannot read is its default', () {
    final prefs = Prefs.decode(
      '{"chat": {"spellcheck": "no", "nope": true, "followAnswer": false}}',
    );
    expect(prefs.isOn(ChatSwitch.spellcheck), isTrue);
    expect(prefs.isOn(ChatSwitch.followAnswer), isFalse);
    expect(Prefs.decode('{"chat": 3}').switches, isEmpty);
  });

  test('the last chat round-trips, and a draft has no chat', () {
    final chat = const Prefs().withLastChat(_s, 'a', 't');
    expect(Prefs.decode(chat.encode()).lastChat, const LastChat('a', 't', _s));
    final draft = const Prefs().withLastChat(_s, 'a', null);
    expect(
      Prefs.decode(draft.encode()).lastChat,
      const LastChat('a', null, _s),
    );
    expect(Prefs.decode(const Prefs().encode()).lastChat, isNull);
  });

  test('a last chat it cannot read is none', () {
    expect(Prefs.decode('{"lastChat": "a"}').lastChat, isNull);
    expect(Prefs.decode('{"lastChat": {"slug": ""}}').lastChat, isNull);
    expect(
      Prefs.decode('{"lastChat": {"slug": "a", "thread": 4}}').lastChat,
      const LastChat('a'),
    );
  });

  test(
    'the last chat follows a renamed workspace and goes with a deleted one',
    () {
      final prefs = const Prefs().withLastChat(_s, 'a', 't');
      expect(
        prefs.withRenamedWorkspace(_s, 'a', 'z').lastChat,
        const LastChat('z', 't', _s),
      );
      expect(prefs.withRenamedWorkspace(_s, 'b', 'z').lastChat, prefs.lastChat);
      expect(prefs.withRenamedWorkspace(_t, 'a', 'z').lastChat, prefs.lastChat);
      expect(prefs.withoutWorkspace(_s, 'a').lastChat, isNull);
      expect(prefs.withoutWorkspace(_s, 'b').lastChat, prefs.lastChat);
      expect(prefs.withoutWorkspace(_t, 'a').lastChat, prefs.lastChat);
      expect(prefs.withTheme(ThemePref.dark).lastChat, prefs.lastChat);
    },
  );

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
    expect(prefs.withRenamedWorkspace(_s, 'b', 'z').workspaceOrder, [
      'a',
      'z',
      'c',
    ]);
    expect(prefs.withRenamedWorkspace(_s, 'b', 'c').workspaceOrder, ['a', 'c']);
  });

  test('switching a document off keeps the other prefs', () {
    final prefs = const Prefs()
        .withTheme(ThemePref.light)
        .withOrder(['a'])
        .withOff(_s, 'a', const [OffDoc(path: 'f/x.json', title: 'x')]);
    expect(prefs.theme, ThemePref.light);
    expect(prefs.workspaceOrder, ['a']);
    expect(prefs.withoutWorkspace(_s, 'a').workspaceOrder, isEmpty);
  });

  test(
    'two servers keep apart what is switched off in same-named workspaces',
    () {
      const a = OffDoc(path: 'f/a.json', title: 'a');
      final prefs = const Prefs().withOff(_s, 'my-workspace', [a]);
      expect(prefs.offIn(_s, 'my-workspace').single.path, 'f/a.json');
      expect(prefs.offIn(_t, 'my-workspace'), isEmpty);
    },
  );

  test('what was saved before servers were told apart goes to the first one', () {
    final prefs = Prefs.decode(
      '{"switchedOff": {"w": [{"path": "f/x.json"}], "$_t w": [{"path": "f/y.json"}]},'
      ' "lastChat": {"slug": "w", "thread": "t1"}}',
    );
    expect(prefs.hasUnowned, isTrue);
    final adopted = prefs.adoptedBy(_s);
    expect(adopted.hasUnowned, isFalse);
    expect(adopted.offIn(_s, 'w').single.path, 'f/x.json');
    expect(adopted.offIn(_t, 'w').single.path, 'f/y.json');
    expect(adopted.lastChat, const LastChat('w', 't1', _s));
    expect(Prefs.decode(adopted.encode()).hasUnowned, isFalse);
  });
}
