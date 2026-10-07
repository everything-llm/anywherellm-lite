import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/providers.dart';
import '../../core/system_settings.dart';
import '../app_scope.dart';
import '../widgets/controls.dart';
import 'rows.dart';
import 'server_settings.dart';

/// Where a question and the passages found for it go: the providers the server uses, and
/// whether it sends its makers anonymous usage data.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final system = AppScope.of(context).system;
    return ServerSettings(
      builder: (values, _) {
        String text(String key) => settingText(values, key);
        final chat = text('LLMProvider');
        final model = text(chatModelKeys[chat] ?? '');
        final embedder = text('EmbeddingEngine');
        final store = text('VectorDB');
        final telemetry = switch (values['DisableTelemetry']) {
          true || 'true' => false,
          _ => true,
        };
        return FieldCard([
          ReadOnlyRow(
            label: 'Chat model',
            value: [
              chatProviders.labelOf(chat),
              if (model.isNotEmpty) model,
            ].join(', '),
            help: 'Your questions and the passages found for them go to it.',
          ),
          ReadOnlyRow(
            label: 'Document search model',
            value: embedderProviders.labelOf(embedder),
            help: embedder == 'native'
                ? 'Runs on the server.'
                : 'Your documents\' text goes to it to be prepared.',
          ),
          ReadOnlyRow(
            label: 'Document storage',
            value: vectorProviders.labelOf(store),
            help: store == 'lancedb'
                ? 'Passages and text stay on the server.'
                : 'Passages and their text are kept there.',
          ),
          FieldRow(
            label: 'Anonymous telemetry',
            help: 'The server sends anonymous usage data to AnythingLLM\'s makers.',
            small: true,
            control: AppSwitch(
              value: telemetry,
              large: true,
              label: 'Anonymous telemetry',
              onChanged: system.saving
                  ? null
                  : (on) => system.saveSettings(
                      jsonEncode({'DisableTelemetry': on ? 'false' : 'true'}),
                    ),
            ),
          ),
        ]);
      },
    );
  }
}
