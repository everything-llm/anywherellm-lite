import 'package:anywherellm/core/shortcuts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('built-in prompt shortcuts expand like the prototype', () {
    final translate = builtInPromptShortcuts.singleWhere(
      (shortcut) => shortcut.id == 'translate',
    );
    final summary = builtInPromptShortcuts.singleWhere(
      (shortcut) => shortcut.id == 'summarize',
    );

    expect(
      translate.expand(' French '),
      'Translate your last answer into French.',
    );
    expect(summary.expand(''), 'Summarise this chat so far in a few lines.');
    expect(
      const PromptShortcut(
        id: 'custom',
        name: 'custom',
        label: 'Custom',
        prompt: 'Summarise {text}.',
      ).expand(''),
      'Summarise',
    );
  });

  test('custom prompts substitute a detail or append it', () {
    const templated = PromptShortcut(
      id: 'formal',
      name: 'formal',
      label: 'Make it formal',
      prompt: 'Rewrite {text} in a formal tone.',
    );
    const plain = PromptShortcut(
      id: 'rewrite',
      name: 'rewrite',
      label: 'Rewrite',
      prompt: 'Rewrite your answer.',
    );

    expect(templated.expand('an email'), 'Rewrite an email in a formal tone.');
    expect(templated.expand(''), 'Rewrite in a formal tone.');
    expect(
      plain.expand('in three sentences'),
      'Rewrite your answer. in three sentences',
    );
  });

  test('shortcut records skip malformed data', () {
    expect(PromptShortcut.fromJson({'name': 'bad'}), isNull);
    expect(ShortcutUse.fromJson({'label': 'Summarise'}), isNull);
    expect(
      PromptShortcut.fromJson({
        'id': 'custom',
        'name': 'custom',
        'label': 'Custom',
        'prompt': 'Do it.',
        'workspaceKey': 'server w',
      })?.workspaceKey,
      'server w',
    );
  });
}
