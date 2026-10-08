import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/providers.dart';
import '../../core/system_settings.dart';
import '../app_scope.dart';
import '../links.dart';
import '../state/system_controller.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/phone_page.dart';
import 'server_settings.dart';
import 'settings_pages.dart';
import 'rows.dart';

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

/// The phone's line for the Server row in Settings' list: the chat model and how many passages
/// the server holds, as far as they have been read.
String serverSummary(SystemController system) {
  final values = system.settings;
  final model = values == null ? '' : systemChatModel(values).model;
  return [
    if (model.isNotEmpty) model,
    if (system.vectors case final count?) '${grouped(count)} passages stored',
  ].join(' · ');
}

/// The phone's Server page: what AnythingLLM runs with, each row showing its value and opening
/// the page that changes it, then a way to AnythingLLM's own web page.
class ServerPage extends StatefulWidget {
  const ServerPage({super.key});

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  @override
  void initState() {
    super.initState();
    final system = AppScope.of(context).system;
    // A read tells the controller's listeners at once, so it waits for the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && system.vectors == null) system.readVectors();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    return ServerSettings(
      builder: (values, _) {
        Widget row(SettingsPage page, [String? value]) => NavRow(
          title: page.label,
          about: value,
          onTap: () => shell.showSettingsPage(page),
        );
        final vectors = scope.system.vectors;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Answers'),
            const SizedBox(height: 6),
            FieldCard([
              row(SettingsPage.chatModel, _chatModel(values)),
              row(SettingsPage.searchModel, _chosen(embedderProviders, values)),
              row(
                SettingsPage.storage,
                [
                  _chosen(vectorProviders, values),
                  if (vectors != null) plural(vectors, 'passage', 'passages'),
                ].join(' · '),
              ),
              row(SettingsPage.images, _chosen(imageProviders, values)),
            ]),
            const SizedBox(height: 18),
            const SectionLabel('Files and voice'),
            const SizedBox(height: 6),
            FieldCard([
              row(
                SettingsPage.transcription,
                _chosen(transcriptionProviders, values),
              ),
              row(SettingsPage.voice, _chosen(textToSpeechProviders, values)),
            ]),
            const SizedBox(height: 18),
            const SectionLabel('Data'),
            const SizedBox(height: 6),
            FieldCard([
              row(SettingsPage.chats),
              row(SettingsPage.embeds),
              row(SettingsPage.privacy),
            ]),
            const SizedBox(height: 18),
            const SectionLabel('Advanced'),
            const SizedBox(height: 6),
            FieldCard([row(SettingsPage.json)]),
            const SizedBox(height: 20),
            if (scope.settings.connection case final connection?)
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  'Open AnythingLLM\'s web page',
                  onPressed: () => openLink(context, connection.uri.toString()),
                ),
              ),
          ],
        );
      },
    );
  }
}
