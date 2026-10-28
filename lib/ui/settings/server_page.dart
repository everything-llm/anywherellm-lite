import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/providers.dart';
import '../../core/system_settings.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../links.dart';
import '../state/system_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/phone_page.dart';
import '../widgets/sheet.dart';
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

/// The Server page: what AnythingLLM runs with, the chat model among them changed here,
/// Privacy and data, then a row that opens AnythingLLM's own web page, where the rest of
/// these are changed.
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
          _ChatModelRow(values: values),
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
            about: 'Change voice, widgets, chat exports and advanced settings there',
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

/// The Chat model row of Running on your server: the provider and model the server answers
/// with, and, on Change, the two of them to answer with instead, asked for as the workspace's
/// own picker asks. Each provider's model is kept under its own setting, so the field names
/// the chosen provider's model; a provider with no such setting, one that serves its own model
/// or the model router, is saved by its name alone.
class _ChatModelRow extends StatefulWidget {
  const _ChatModelRow({required this.values});

  /// The server's settings as the page shows them, which the row gives until a save takes new
  /// ones into them.
  final Map<String, Object?> values;

  @override
  State<_ChatModelRow> createState() => _ChatModelRowState();
}

class _ChatModelRowState extends State<_ChatModelRow> {
  bool _editing = false;
  String _provider = '';
  final _model = TextEditingController();

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  /// Opens the editor on the server's provider and the model it keeps for it. A server that
  /// names no provider starts on the first the app offers: there is no model above this one
  /// to fall back on, as a workspace falls back on it.
  void _open() {
    final settings = AppScope.of(context).system.settings;
    final provider = systemChatModel(settings).provider;
    setState(() {
      _provider = provider.isEmpty
          ? chatProviders
                .choices('')
                .firstWhere((value) => value.isNotEmpty, orElse: () => '')
          : provider;
      _model.text = settingText(settings, chatModelKeys[_provider] ?? '');
      _editing = true;
    });
  }

  /// Chooses [provider] and names its model in the field: the server keeps each provider's
  /// model apart, so the field shows the chosen one's, not the one before it.
  void _choose(String? provider) {
    final settings = AppScope.of(context).system.settings;
    setState(() {
      _provider = provider ?? '';
      _model.text = settingText(settings, chatModelKeys[_provider] ?? '');
    });
  }

  /// Writes the chosen provider and, where it has a model setting, the model named, and
  /// closes the editor once the server has taken them. A save that failed leaves the editor
  /// open, with why it failed over the page.
  Future<void> _save() async {
    final saved = await AppScope.of(context).system.saveSettings({
      'LLMProvider': _provider,
      ?chatModelKeys[_provider]: _model.text.trim(),
    });
    if (saved && mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final saving = AppScope.of(context).system.saving;
    return Container(
      constraints: BoxConstraints(
        minHeight: SheetFrame.holds(context) ? Sizes.cardRow : Sizes.pageRow,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: FieldCard.inset,
        vertical: 10,
      ),
      child: _editing ? _editor(context, saving) : _shown(context, saving),
    );
  }

  /// The provider and model as they stand, and the Change that opens the editor on them.
  Widget _shown(BuildContext context, bool saving) {
    final t = Tokens.of(context);
    return Row(
      spacing: 12,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Chat model', style: Type.body(t.ink)),
              Text(
                _chatModel(widget.values),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.note(t.ink),
              ),
            ],
          ),
        ),
        AppButton('Change', quiet: true, onPressed: saving ? null : _open),
      ],
    );
  }

  /// The provider to answer with and, where it names its model by a setting, that model.
  Widget _editor(BuildContext context, bool saving) {
    final t = Tokens.of(context);
    // The providers the server takes, in the order the app lists them.
    final choices = chatProviders
        .choices(_provider)
        .where((value) => value.isNotEmpty)
        .toList();
    return Semantics(
      container: true,
      label: 'Chat model',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Chat model',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.caption(t.ink, weight: FontWeight.w600),
                ),
              ),
              IconBtn(
                'close',
                tooltip: 'Cancel',
                box: 28,
                size: IconSize.xs,
                onPressed: saving
                    ? null
                    : () => setState(() => _editing = false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppSelect(
            value: _provider,
            choices: choices,
            labelOf: chatProviders.labelOf,
            onChanged: saving ? null : _choose,
          ),
          if (chatModelKeys[_provider] != null) ...[
            const SizedBox(height: 8),
            AppField(
              controller: _model,
              label: 'Model',
              hint: "In the provider's own name for it.",
            ),
          ] else ...[
            const SizedBox(height: 6),
            const HelpText(
              'This provider answers with a model of its own, so there is none to name.',
            ),
          ],
          const SizedBox(height: 10),
          ActionRow([
            AppButton(
              saving ? 'Saving…' : 'Save',
              primary: true,
              onPressed: saving ? null : _save,
            ),
          ]),
        ],
      ),
    );
  }
}
