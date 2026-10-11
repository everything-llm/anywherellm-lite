import 'package:flutter/material.dart';

import '../../core/prefs.dart';
import '../app_scope.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
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
            // A phone puts each name over its choices, with no card, as the design canvas
            // draws it, and says what the text size does once, under both.
            if (phone) ...[
              _Named('Theme', theme),
              _Named('Chat text size', size),
              const HelpText(
                'Text size scales the chat\'s turns, not the controls around them.',
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

/// [control] under its [name], which a screen reader hears as the group's.
class _Named extends StatelessWidget {
  const _Named(this.name, this.control);

  final String name;
  final Widget control;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: name,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        ExcludeSemantics(
          child: Text(
            name,
            style: Type.sans(
              15,
              weight: FontWeight.w500,
              color: Tokens.of(context).ink,
            ),
          ),
        ),
        control,
      ],
    ),
  );
}

/// What the Chat page holds, as a phone's Settings list says it: the switches this device has.
String chatSummary(AppScope scope) {
  final parts = [
    if (scope.dictation != null) 'dictation',
    if (scope.readAloud != null) 'reading aloud',
    if (scope.canSpellcheck) 'spellcheck',
    'answer details',
  ];
  final line = parts.join(', ');
  return line[0].toUpperCase() + line.substring(1);
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
