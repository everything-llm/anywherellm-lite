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

/// What each provider page of the server says it is set to, by page; null for one that is not
/// set up.
Map<SettingsPage, String?> _summaries(
  SystemController system,
  Map<String, Object?> values,
) {
  final vectors = system.vectors;
  final speech = _chosen(speechToTextProviders, values);
  final speaking = _chosen(textToSpeechProviders, values);
  return {
    SettingsPage.chatModel: _chatModel(values),
    SettingsPage.searchModel: _chosen(embedderProviders, values),
    SettingsPage.storage: [
      _chosen(vectorProviders, values),
      if (vectors != null) plural(vectors, 'passage', 'passages'),
    ].join(' \u00b7 '),
    SettingsPage.transcription: _chosen(transcriptionProviders, values),
    SettingsPage.voice: speech == speaking
        ? speech
        : '$speech \u00b7 $speaking',
    // An image provider that is not chosen is not set up.
    SettingsPage.images: settingText(values, imageProviders.chooser).isEmpty
        ? null
        : _chosen(imageProviders, values),
  };
}

/// The Server page: what AnythingLLM runs with, the pages in four groups, each row showing its
/// value and opening the page that changes it, then a way to AnythingLLM's own web page.
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
    return ServerSettings(
      builder: (values, _) {
        return _page(context, _summaries(scope.system, values));
      },
    );
  }

  /// Four groups of rows, then a way to AnythingLLM's web page.
  Widget _page(BuildContext context, Map<SettingsPage, String?> summaries) {
    final shell = AppScope.of(context).shell;
    Widget row(SettingsPage page, [String? value]) => NavRow(
      title: page.label,
      about: value,
      onTap: () => shell.showSettingsPage(page),
    );
    Widget group(String label, List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [SectionLabel(label), FieldCard(rows)],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 18,
      children: [
        group('Answers', [
          row(SettingsPage.chatModel, summaries[SettingsPage.chatModel]),
          row(SettingsPage.searchModel, summaries[SettingsPage.searchModel]),
          row(SettingsPage.storage, summaries[SettingsPage.storage]),
          row(SettingsPage.images, summaries[SettingsPage.images] ?? 'None'),
        ]),
        group('Files and voice', [
          row(
            SettingsPage.transcription,
            summaries[SettingsPage.transcription],
          ),
          row(SettingsPage.voice, summaries[SettingsPage.voice]),
        ]),
        group('Data', [
          row(SettingsPage.chats),
          row(SettingsPage.embeds),
          row(SettingsPage.privacy),
        ]),
        group('Advanced', [row(SettingsPage.json)]),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            'Open AnythingLLM\'s web page',
            onPressed: () => openServerPage(context),
          ),
        ),
      ],
    );
  }
}
