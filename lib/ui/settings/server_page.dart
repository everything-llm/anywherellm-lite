import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/providers.dart';
import '../../core/system_settings.dart';
import '../app_scope.dart';
import '../links.dart';
import '../state/system_controller.dart';
import '../widgets/phone_page.dart';
import 'rows.dart';
import 'server_settings.dart';
import 'settings_pages.dart';

/// What [setting] is set to in [values], by its name.
String _chosen(ProviderSetting setting, Map<String, Object?> values) =>
    setting.labelOf(settingText(values, setting.chooser));

/// The chat model the server answers with and its provider, as `glm-5.3 · Generic OpenAI`.
String _chatModel(Map<String, Object?> values) {
  final (:provider, :model) = systemChatModel(values);
  return [
    if (model.isNotEmpty) model,
    chatProviders.labelOf(provider),
  ].join(' · ');
}

/// The line for the Server row in Settings' list: the chat model and how many passages
/// the server holds, as far as they have been read.
String serverSummary(SystemController system) {
  final values = system.settings;
  final model = values == null ? '' : systemChatModel(values).model;
  return [
    if (model.isNotEmpty) model,
    if (system.vectors case final count?) '${grouped(count)} passages stored',
  ].join(' · ');
}

/// The Server page, read only: what AnythingLLM runs with, Privacy and data, then a row that
/// opens AnythingLLM's own web page, where every one of these is changed.
class ServerPage extends StatefulWidget {
  const ServerPage({super.key});

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  @override
  void initState() {
    super.initState();
    AppScope.of(context).system.wantVectors();
  }

  @override
  Widget build(BuildContext context) {
    return ServerSettings(builder: (values) => _page(context, values));
  }

  /// Running on your server, then Your data, then the web page.
  Widget _page(BuildContext context, Map<String, Object?> values) {
    final scope = AppScope.of(context);
    final vectors = scope.system.vectors;
    final speech = _chosen(speechToTextProviders, values);
    final speaking = _chosen(textToSpeechProviders, values);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CardHeading('Running on your server', top: 0),
        FieldCard([
          InfoRow('Chat model', about: _chatModel(values)),
          InfoRow(
            'Document search model',
            about: _chosen(embedderProviders, values),
          ),
          InfoRow(
            'Document storage',
            about: [
              _chosen(vectorProviders, values),
              if (vectors != null) plural(vectors, 'passage', 'passages'),
            ].join(' \u00b7 '),
          ),
          InfoRow(
            'Transcription',
            about: _chosen(transcriptionProviders, values),
          ),
          InfoRow(
            'Voice and speech',
            about: speech == speaking ? speech : '$speech \u00b7 $speaking',
          ),
        ]),
        const CardHeading('Your data'),
        FieldCard([
          NavRow(
            title: SettingsPage.privacy.label,
            about: 'Where your questions go',
            onTap: () => scope.shell.showSettingsPage(SettingsPage.privacy),
          ),
        ]),
        const SizedBox(height: 20),
        FieldCard([
          NavRow(
            title: 'Open AnythingLLM\'s web page',
            about: 'Change models, voice, widgets, chat exports and advanced settings there',
            aboutLines: 2,
            end: 'external',
            accent: true,
            onTap: () => openServerPage(context),
          ),
        ]),
      ],
    );
  }
}
