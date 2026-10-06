import 'package:anywherellm/core/commands.dart';
import 'package:flutter_test/flutter_test.dart';

const _research = SlashCommand(
  command: '/deep-research',
  prompt: '@agent Research this:',
  description: 'Research a question in depth',
);
const _clear = SlashCommand(command: '/clear', prompt: '/reset');

void main() {
  group('fromJson', () {
    test('reads a preset', () {
      final c = SlashCommand.fromJson({
        'id': 1,
        'command': '/deep-research',
        'prompt': 'p',
        'description': 'd',
      })!;
      expect(
        (c.command, c.prompt, c.description),
        ('/deep-research', 'p', 'd'),
      );
    });

    test('a preset with no slash command is left out', () {
      expect(SlashCommand.fromJson({'command': 'x', 'prompt': 'p'}), isNull);
      expect(SlashCommand.fromJson({'prompt': 'p'}), isNull);
    });
  });

  test('the built-in comes first, and a preset named like it is left out', () {
    final all = withBuiltIns([
      _research,
      const SlashCommand(command: '/RESET', prompt: 'x'),
    ]);
    expect([for (final c in all) c.command], ['/reset', '/deep-research']);
  });

  group('commandsFor', () {
    final all = withBuiltIns([_research, _clear]);
    List<String> offered(String draft) => [
      for (final c in commandsFor(draft, all)) c.command,
    ];

    test('a slash offers every command', () {
      expect(offered('/'), ['/reset', '/deep-research', '/clear']);
    });

    test('more letters narrow it, ignoring case', () {
      expect(offered('/DE'), ['/deep-research']);
      expect(offered('/x'), isEmpty);
    });

    test('nothing once a space follows, or without a leading slash', () {
      expect(offered('/deep-research '), isEmpty);
      expect(offered('a /'), isEmpty);
      expect(offered(''), isEmpty);
    });
  });

  group('expandPresets', () {
    test('swaps a preset at the start or after a space', () {
      expect(
        expandPresets('/deep-research tides', [_research]),
        '@agent Research this: tides',
      );
      expect(
        expandPresets('then /deep-research', [_research]),
        'then @agent Research this:',
      );
    });

    test('leaves a longer command and a mid-word slash alone', () {
      expect(
        expandPresets('/deep-research-x a/deep-research', [_research]),
        '/deep-research-x a/deep-research',
      );
    });
  });

  group('resetsChat', () {
    test('/reset alone or with more, in any case', () {
      expect(resetsChat('/reset', const []), isTrue);
      expect(resetsChat('  /Reset now', const []), isTrue);
    });

    test('a preset whose prompt is /reset', () {
      expect(resetsChat('/clear', [_clear]), isTrue);
      expect(resetsChat('/clear', const []), isFalse);
    });

    test('not a longer command, nor /reset later in the message', () {
      expect(resetsChat('/reset-all', const []), isFalse);
      expect(resetsChat('please /reset', const []), isFalse);
    });
  });
}
