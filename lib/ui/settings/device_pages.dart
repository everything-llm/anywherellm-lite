import 'package:flutter/material.dart';

import '../../core/prefs.dart';
import '../app_scope.dart';
import '../layout.dart';
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
    final phone = ScreenClass.ofContext(context).isPhone;
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
          spacing: phone ? 20 : 12,
          children: [
            // A phone puts each name over its choices in a card of its own, as the design
            // canvas draws it.
            if (phone) ...[
              PanelCard(children: [NamedControl('Theme', theme, size: 17)]),
              PanelCard(
                children: [NamedControl('Chat text size', size, size: 17)],
              ),
            ] else
              FieldCard([
                FieldRow(label: 'Theme', control: theme),
                FieldRow(
                  label: 'Chat text size',
                  help:
                      'Scales the chat\'s turns, not the controls around them.',
                  control: size,
                ),
              ]),
            if (prefs.problem case final problem?)
              HelpText('${problem.title}. ${problem.text}', status: true),
          ],
        );
      },
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
        'Keeps the newest text in view unless you have scrolled up.',
      ),
      (
        ChatSwitch.answerDetails,
        'Show answer details',
        'The model, time, tokens, speed and cost under every answer.',
      ),
    ];
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          FieldCard([
            // A phone names each switch alone, as the design canvas draws them.
            for (final (which, label, help) in rows)
              FieldRow(
                label: label,
                help: ScreenClass.ofContext(context).isPhone ? '' : help,
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
