import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/providers.dart';
import '../../core/system_settings.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../links.dart';
import '../state/system_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/phone_page.dart';
import '../widgets/tappable.dart';
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

/// The Server page: what AnythingLLM runs with, each row showing its value and opening the page
/// that changes it. A [phone] lists the pages in four groups and ends with a way to AnythingLLM's
/// own web page. Elsewhere three groups are followed by three folds: what is not set up yet,
/// AnythingLLM's pages that the app leaves to its web page, and Advanced.
class ServerPage extends StatefulWidget {
  const ServerPage({super.key, this.phone = false});

  final bool phone;

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  /// The folds of the page that is not a phone's.
  bool _unset = false;
  bool _web = false;
  bool _advanced = false;

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
        if (!widget.phone) return _wide(context, values);
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

  /// The page beside the list: the pages in three groups, then the folds.
  Widget _wide(BuildContext context, Map<String, Object?> values) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final vectors = scope.system.vectors;
    final speech = _chosen(speechToTextProviders, values);
    final speaking = _chosen(textToSpeechProviders, values);
    final settled = {
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
      SettingsPage.chats: 'Browse and export',
      SettingsPage.embeds: switch (scope.system.embeds) {
        final embeds? => plural(embeds.length, 'widget', 'widgets'),
        null => '',
      },
      SettingsPage.privacy: switch (values['DisableTelemetry']) {
        true || 'true' => 'Anonymous telemetry off',
        _ => 'Anonymous telemetry on',
      },
    };
    const groups = [
      (
        'Answers',
        [
          SettingsPage.chatModel,
          SettingsPage.searchModel,
          SettingsPage.storage,
        ],
      ),
      (
        'Files, voice and images',
        [SettingsPage.transcription, SettingsPage.voice, SettingsPage.images],
      ),
      (
        'Sharing and records',
        [SettingsPage.chats, SettingsPage.embeds, SettingsPage.privacy],
      ),
    ];
    final notSetUp = [
      for (final (_, pages) in groups)
        for (final page in pages)
          if (settled[page] == null && page == SettingsPage.images) page,
    ];
    Widget go(SettingsPage page, String? value) => _SummaryRow(
      page.label,
      value ?? '',
      onTap: () => shell.showSettingsPage(page),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 18,
      children: [
        for (final (label, pages) in groups)
          if ([
                for (final page in pages)
                  if (!notSetUp.contains(page)) page,
              ]
              case final shown when shown.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                SectionLabel(label),
                FieldCard([for (final page in shown) go(page, settled[page])]),
              ],
            ),
        if (notSetUp.isNotEmpty)
          _Folded(
            'Not set up (${notSetUp.length})',
            open: _unset,
            onToggle: () => setState(() => _unset = !_unset),
            rows: [for (final page in notSetUp) go(page, 'Set up')],
          ),
        _Folded(
          'In AnythingLLM\'s web page (${webPages.length})',
          open: _web,
          onToggle: () => setState(() => _web = !_web),
          note: scope.settings.connection == null
              ? null
              : 'These open ${scope.settings.connection!.uri.host} in the browser. They are '
                    'rarely changed, and changing them needs the server password.',
          rows: [
            for (final web in webPages)
              _SummaryRow(
                web.label,
                'Opens in the browser',
                out: true,
                onTap: () {
                  if (scope.settings.connection case final connection?) {
                    openLink(context, connection.uri.toString());
                  }
                },
              ),
          ],
        ),
        _Folded(
          'Advanced',
          open: _advanced,
          onToggle: () => setState(() => _advanced = !_advanced),
          rows: [
            go(SettingsPage.json, 'Every setting, as the server stores it'),
          ],
        ),
      ],
    );
  }
}

/// A fold with rows in a card under it, and a line under that, once opened.
class _Folded extends StatelessWidget {
  const _Folded(
    this.label, {
    required this.open,
    required this.onToggle,
    required this.rows,
    this.note,
  });

  final String label;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> rows;
  final String? note;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      Fold(label: label, open: open, onToggle: onToggle),
      if (open) ...[FieldCard(rows), if (note case final note?) HelpText(note)],
    ],
  );
}

/// A row of the Server page beside the list: the page's name, what it is set to and a chevron,
/// or, for a page that opens in the browser, an arrow out.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow(
    this.label,
    this.value, {
    required this.onTap,
    this.out = false,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final bool out;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: [label, if (value.isNotEmpty) value].join(', '),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.fromLTRB(16, 8, 14, 8),
        child: Row(
          spacing: 12,
          children: [
            SizedBox(
              width: 200,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.sans(14.5, weight: FontWeight.w500, color: t.ink),
              ),
            ),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.sans(13.5, color: t.ink2),
              ),
            ),
            AppIcon(
              out ? 'external' : 'chevron',
              size: IconSize.xs,
              color: t.muted,
            ),
          ],
        ),
      ),
    );
  }
}
