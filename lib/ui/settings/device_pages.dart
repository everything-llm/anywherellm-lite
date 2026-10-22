import 'package:flutter/material.dart';

import '../../core/prefs.dart';
import '../app_scope.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/fields.dart';
import '../widgets/phone_page.dart';
import '../widgets/rise.dart';
import '../widgets/segmented.dart';
import 'rows.dart';
import 'settings_pages.dart';

/// The theme, and the size of a chat's text.
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = AppScope.of(context).prefs;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final theme = Segmented<ThemePref>(
          options: const [
            (ThemePref.system, 'System'),
            (ThemePref.light, 'Light'),
            (ThemePref.dark, 'Dark'),
          ],
          value: prefs.prefs.theme,
          onChanged: prefs.setTheme,
        );
        final size = Segmented<TextSize>(
          options: const [
            (TextSize.small, 'Small'),
            (TextSize.normal, 'Normal'),
            (TextSize.large, 'Large'),
          ],
          value: prefs.prefs.textSize,
          onChanged: prefs.setTextSize,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 20,
          children: [
            // Each name sits over its choices in a card of its own, as the Lite prototype
            // draws it.
            PanelCard(children: [NamedControl('Theme', theme)]),
            PanelCard(
              children: [
                NamedControl('Chat text size', size),
                _SizePreview(prefs.prefs.textSize),
              ],
            ),
            if (prefs.problem case final problem?)
              HelpText('${problem.title}. ${problem.text}', status: true),
          ],
        );
      },
    );
  }
}

/// A line set as an answer is, at the chat text [size] chosen, so the choice can be judged
/// before leaving the page.
class _SizePreview extends StatelessWidget {
  const _SizePreview(this.size);

  final TextSize size;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return AnimatedSize(
      duration: motion(context, const Duration(milliseconds: 150)),
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: t.ground,
          borderRadius: BorderRadius.circular(Sizes.control),
          border: Border.all(color: t.line),
        ),
        child: Text(
          'An answer in the chat reads like this.',
          style: Type.sans(Type.chat * size.scale, color: t.ink, height: 1.5),
        ),
      ),
    );
  }
}

/// How the chat behaves on this device: each [ChatSwitch] the device can use.
class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final prefs = scope.prefs;
    final rows = [
      if (scope.dictation != null)
        (
          ChatSwitch.sendDictation,
          'Send when I stop talking',
          'Sends a dictated message once you pause, instead of leaving it in the box.',
        ),
      if (scope.readAloud != null)
        (
          ChatSwitch.readAnswers,
          'Read answers aloud',
          'Reads each answer out as soon as it finishes.',
        ),
      if (scope.canSpellcheck)
        (
          ChatSwitch.spellcheck,
          'Spellcheck the message',
          'Marks misspelled words in the message box.',
        ),
      (
        ChatSwitch.followAnswer,
        'Follow a streaming answer',
        'Keeps the newest words in view while an answer is written.',
      ),
      (
        ChatSwitch.answerDetails,
        'Show answer details',
        'Shows the model, time, tokens, speed and cost under every answer.',
      ),
      (
        ChatSwitch.hideShortcutPrompts,
        'Hide a shortcut’s prompt',
        'Shows a chip for a shortcut you sent, not the question it expanded to.',
      ),
    ];
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          FieldCard([
            // Each switch is named alone, as the Lite prototype draws them.
            for (final (which, label, help) in rows)
              FieldRow.toggle(
                label: label,
                help: help,
                value: prefs.prefs.isOn(which),
                onChanged: (on) => prefs.setSwitch(which, on),
              ),
          ]),
          FieldCard([
            NavRow(
              icon: 'slash',
              title: 'Shortcuts',
              about:
                  '${scope.prefs.shortcutsIn(scope.chat.activeSlug).length} prompts · type / to use them',
              onTap: () => scope.shell.showSettingsPage(SettingsPage.shortcuts),
            ),
          ]),
          if (prefs.problem case final problem?)
            HelpText('${problem.title}. ${problem.text}', status: true),
        ],
      ),
    );
  }
}
