import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/providers.dart';
import '../app_scope.dart';
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
        final telemetry = switch (values['DisableTelemetry']) {
          true || 'true' => false,
          _ => true,
        };
        return FieldCard([
          ReadOnlyRow(label: 'Chat model', value: chatModelPrivacy(values)),
          ReadOnlyRow(
            label: 'Document search model',
            value: searchModelPrivacy(values),
          ),
          ReadOnlyRow(label: 'Document storage', value: storagePrivacy(values)),
          FieldRow.toggle(
            label: 'Anonymous telemetry',
            help: 'The server sends anonymous usage data to AnythingLLM\'s makers.',
            value: telemetry,
            onChanged: system.saving
                ? null
                : (on) => system.saveSettings(
                    jsonEncode({'DisableTelemetry': on ? 'false' : 'true'}),
                  ),
          ),
        ]);
      },
    );
  }
}
