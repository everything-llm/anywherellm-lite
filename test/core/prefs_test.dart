import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/core/shortcuts.dart';
import 'package:flutter_test/flutter_test.dart';

const _s = 'https://s:3001';
const _t = 'https://t:3001';

void main() {
  test('the folder used last round-trips, by server', () {
    final prefs = const Prefs()
        .withLastFolder(_s, 'Manuals')
        .withLastFolder(_t, 'Bills and papers');
    final back = Prefs.decode(prefs.encode());
    expect(back.lastFolders, {_s: 'Manuals', _t: 'Bills and papers'});
    expect(const Prefs().encode(), isNot(contains('lastFolders')));
  });

  test('shortcuts and their sent exchange details round-trip', () {
    const shortcut = PromptShortcut(
      id: 'formal',
      name: 'formal',
      label: 'Make it formal',
      prompt: 'Rewrite {text} formally.',
      workspaceKey: '$_s q3',
    );
    const use = ShortcutUse(label: 'Translate', detail: 'French');
    final prefs = const Prefs(shortcuts: [shortcut])
        .withShortcutUse(Prefs.shortcutUseKey(_s, 'q3', 'thread', 42), use);

    final back = Prefs.decode(prefs.encode());
    expect(back.shortcuts.single.toJson(), shortcut.toJson());
    expect(
      back.shortcutUses[Prefs.shortcutUseKey(_s, 'q3', 'thread', 42)]?.toJson(),
      use.toJson(),
    );
  });

  test('text that is not its JSON reads as the defaults', () {
    for (final text in ['', 'nope', '[]', '{"lastFolders": 3}']) {
      final prefs = Prefs.decode(text);
      expect(prefs.lastFolders, isEmpty, reason: text);
      expect(prefs.workspaceOrder, isEmpty, reason: text);
    }
  });

  test(
    'an old file with the answers switch and switched-off documents loads',
    () {
      final prefs = Prefs.decode(
        '{"groundedOnly": true, "switchedOff": {"w": [{"path": "f/x.json"}]},'
        ' "workspaceOrder": ["w"]}',
      );
      expect(prefs.workspaceOrder, ['w']);
      expect(prefs.hasUnowned, isFalse);
      expect(prefs.encode(), isNot(contains('groundedOnly')));
      expect(prefs.encode(), isNot(contains('switchedOff')));
    },
  );

  test('a folder it cannot read is skipped', () {
    final prefs = Prefs.decode(
      '{"lastFolders": {"$_s": "", "$_t": 7, "https://u": "Manuals"}}',
    );
    expect(prefs.lastFolders, {'https://u': 'Manuals'});
  });

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
    expect(back.isOn(ChatSwitch.answerDetails), isFalse);
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

  test('the folder used last keeps the other prefs', () {
    final prefs = const Prefs()
        .withTheme(ThemePref.light)
        .withOrder(['a'])
        .withLastFolder(_s, 'Manuals');
    expect(prefs.theme, ThemePref.light);
    expect(prefs.workspaceOrder, ['a']);
    expect(prefs.withoutWorkspace(_s, 'a').lastFolders, {_s: 'Manuals'});
  });

  test(
    'what was saved before servers were told apart goes to the first one',
    () {
      final prefs = Prefs.decode('{"lastChat": {"slug": "w", "thread": "t1"}}');
      expect(prefs.hasUnowned, isTrue);
      final adopted = prefs.adoptedBy(_s);
      expect(adopted.hasUnowned, isFalse);
      expect(adopted.lastChat, const LastChat('w', 't1', _s));
      expect(Prefs.decode(adopted.encode()).hasUnowned, isFalse);
    },
  );

  group('pinned and recent chats', () {
    test('round-trip through its JSON, by server and workspace', () {
      final prefs = const Prefs()
          .withPin(_s, 'q3', 'a', on: true)
          .withPin(_t, 'q3', 'b', on: true)
          .withUse(_s, 'q3', 'c');
      final back = Prefs.decode(prefs.encode());
      expect(back.pinnedIn(_s, 'q3'), ['a']);
      expect(back.pinnedIn(_t, 'q3'), ['b']);
      expect(back.recentIn(_s, 'q3'), ['c']);
      expect(back.recentIn(_t, 'q3'), isEmpty);
    });

    test('a pin comes off, and the last one takes its key with it', () {
      final prefs = const Prefs()
          .withPin(_s, 'q3', 'a', on: true)
          .withPin(_s, 'q3', 'a', on: false);
      expect(prefs.pinnedIn(_s, 'q3'), isEmpty);
      expect(prefs.pinned, isEmpty);
    });

    test('Recent keeps the last used, last used first', () {
      var prefs = const Prefs();
      for (var i = 0; i < Prefs.recentMax + 3; i++) {
        prefs = prefs.withUse(_s, 'q3', 't$i');
      }
      final used = prefs.recentIn(_s, 'q3');
      expect(used, hasLength(Prefs.recentMax));
      expect(used.first, 't12');
      expect(used, isNot(contains('t0')));
      expect(prefs.withUse(_s, 'q3', 't5').recentIn(_s, 'q3').first, 't5');
    });

    test('a deleted chat and a deleted workspace are forgotten', () {
      final prefs = const Prefs()
          .withPin(_s, 'q3', 'a', on: true)
          .withUse(_s, 'q3', 'a')
          .withUse(_s, 'q3', 'b')
          .withPin(_s, 'home', 'h', on: true);
      final noChat = prefs.withoutChat(_s, 'q3', 'a');
      expect(noChat.pinnedIn(_s, 'q3'), isEmpty);
      expect(noChat.recentIn(_s, 'q3'), ['b']);
      final noWorkspace = prefs.withoutWorkspace(_s, 'q3');
      expect(noWorkspace.pinnedIn(_s, 'q3'), isEmpty);
      expect(noWorkspace.recentIn(_s, 'q3'), isEmpty);
      expect(noWorkspace.pinnedIn(_s, 'home'), ['h']);
    });

    test('move with a workspace whose slug changes', () {
      final prefs = const Prefs()
          .withPin(_s, 'q3', 'a', on: true)
          .withUse(_s, 'q3', 'b')
          .withRenamedWorkspace(_s, 'q3', 'q4');
      expect(prefs.pinnedIn(_s, 'q4'), ['a']);
      expect(prefs.recentIn(_s, 'q4'), ['b']);
      expect(prefs.pinnedIn(_s, 'q3'), isEmpty);
    });

    test('that are not its JSON are left out', () {
      final prefs = Prefs.decode(
        '{"pinned": {"k": [1, "a"], "j": "x"}, "recent": {"k": [true, "b"], "j": {"a": 1}}}',
      );
      expect(prefs.pinned, {
        'k': ['a'],
      });
      expect(prefs.recent, {
        'k': ['b'],
      });
    });
  });

  group('messages waiting in a chat', () {
    const server = 'https://llm.example';
    final prefs = const Prefs().withOnDeck(server, 'plans', 't1', const [
      SavedOnDeck(
        'And French?',
        shortcutUse: ShortcutUse(label: 'Translate', detail: 'French'),
      ),
      SavedOnDeck('This one', files: ['notes.pdf']),
    ]);

    test('round-trip, with their shortcut and the names of their files', () {
      final read = Prefs.decode(prefs.encode());
      final kept = read.onDeckIn(server, 'plans', 't1');
      expect(kept.map((m) => m.text), ['And French?', 'This one']);
      expect(kept.first.shortcutUse?.detail, 'French');
      expect(kept.last.files, ['notes.pdf']);
    });

    test('none are dropped from the file', () {
      final none = prefs.withOnDeck(server, 'plans', 't1', const []);
      expect(none.onDeck, isEmpty);
      expect(none.encode(), isNot(contains('onDeck')));
    });

    test('follow a workspace renamed, and go with it or its chat deleted', () {
      final moved = prefs.withRenamedWorkspace(server, 'plans', 'plans-2');
      expect(moved.onDeckIn(server, 'plans', 't1'), isEmpty);
      expect(moved.onDeckIn(server, 'plans-2', 't1'), hasLength(2));
      expect(prefs.withoutWorkspace(server, 'plans').onDeck, isEmpty);
      expect(prefs.keepsChat(server, 'plans', 't1'), isTrue);
      expect(prefs.withoutChat(server, 'plans', 't1').onDeck, isEmpty);
    });
  });

  test('Main chat, whose key names its workspace, follows a slug change', () {
    const use = ShortcutUse(label: 'Translate', detail: 'French');
    final prefs = const Prefs()
        .withLastChat(_s, 'plans', mainChatOf('plans'))
        .withOnDeck(_s, 'plans', mainChatOf('plans'), const [
          SavedOnDeck('And French?'),
        ])
        .withShortcutUse(
          Prefs.shortcutUseKey(_s, 'plans', mainChatOf('plans'), 42),
          use,
        );
    final moved = prefs.withRenamedWorkspace(_s, 'plans', 'plans-2');
    expect(moved.lastChat, LastChat('plans-2', mainChatOf('plans-2'), _s));
    expect(moved.onDeckIn(_s, 'plans-2', mainChatOf('plans-2')), hasLength(1));
    expect(moved.shortcutUses.keys, [
      Prefs.shortcutUseKey(_s, 'plans-2', mainChatOf('plans-2'), 42),
    ]);
    // A thread of the workspace keeps its slug.
    expect(
      const Prefs()
          .withLastChat(_s, 'plans', 't1')
          .withRenamedWorkspace(_s, 'plans', 'plans-2')
          .lastChat,
      const LastChat('plans-2', 't1', _s),
    );
  });
}
