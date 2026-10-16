import 'package:flutter/material.dart';

import '../../core/prefs.dart';
import '../app_scope.dart';
import '../widgets/fields.dart';
import '../widgets/phone_page.dart';
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
            PanelCard(children: [NamedControl('Chat text size', size)]),
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
        (ChatSwitch.sendDictation, 'Send dictation when I stop talking'),
      if (scope.readAloud != null)
        (ChatSwitch.readAnswers, 'Read answers aloud'),
      if (scope.canSpellcheck)
        (ChatSwitch.spellcheck, 'Spellcheck the message'),
      (ChatSwitch.followAnswer, 'Follow a streaming answer'),
      (ChatSwitch.answerDetails, 'Show answer details'),
      (ChatSwitch.hideShortcutPrompts, 'Hide a shortcut’s prompt'),
    ];
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          FieldCard([
            // Each switch is named alone, as the Lite prototype draws them.
            for (final (which, label) in rows)
              FieldRow.toggle(
                label: label,
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
