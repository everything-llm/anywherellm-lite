import 'package:flutter/material.dart';

import '../../core/prefs.dart';
import '../app_scope.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';
import '../widgets/segmented.dart';
import 'rows.dart';

/// The theme, and the size of a chat's text.
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = AppScope.of(context).prefs;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          FieldCard([
            FieldRow(
              label: 'Theme',
              control: Segmented<ThemePref>(
                options: const [
                  (ThemePref.system, 'System'),
                  (ThemePref.light, 'Light'),
                  (ThemePref.dark, 'Dark'),
                ],
                value: prefs.prefs.theme,
                onChanged: prefs.setTheme,
              ),
            ),
            FieldRow(
              label: 'Chat text size',
              help: 'Scales the chat\'s turns, not the controls around them.',
              control: Segmented<TextSize>(
                options: const [
                  (TextSize.small, 'Small'),
                  (TextSize.normal, 'Normal'),
                  (TextSize.large, 'Large'),
                ],
                value: prefs.prefs.textSize,
                onChanged: prefs.setTextSize,
              ),
            ),
          ]),
          if (prefs.problem case final problem?)
            HelpText('${problem.title}. ${problem.text}', status: true),
        ],
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
          'Send dictation when I stop talking',
          'Otherwise the words wait in the message box.',
        ),
      if (scope.readAloud != null)
        (
          ChatSwitch.readAnswers,
          'Read answers aloud',
          'Each finished answer is read as soon as it arrives.',
        ),
      if (scope.canSpellcheck)
        (ChatSwitch.spellcheck, 'Spellcheck the message', ''),
      (
        ChatSwitch.followAnswer,
        'Follow a streaming answer',
        'Keep the newest text in view while it arrives, unless you have scrolled up.',
      ),
      (
        ChatSwitch.reasoningOpen,
        'Show reasoning open',
        'Unfold a model\'s reasoning instead of folding it behind Show reasoning.',
      ),
    ];
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          FieldCard([
            for (final (which, label, help) in rows)
              FieldRow(
                label: label,
                help: help,
                small: true,
                control: AppSwitch(
                  value: prefs.prefs.isOn(which),
                  large: true,
                  label: label,
                  onChanged: (on) => prefs.setSwitch(which, on),
                ),
              ),
          ]),
          if (prefs.problem case final problem?)
            HelpText('${problem.title}. ${problem.text}', status: true),
        ],
      ),
    );
  }
}
