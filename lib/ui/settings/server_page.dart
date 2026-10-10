import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/embeds.dart';
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
/// The website chat widgets in a line: how many, and the workspaces they answer from while there
/// are one or two.
String _widgets(List<Embed> embeds) {
  final count = plural(embeds.length, 'widget', 'widgets');
  final on = {for (final embed in embeds) embed.workspace}.toList();
  return switch (on) {
    [] => count,
    [final one] => '$count, on $one',
    [final one, final two] => '$count, on $one and $two',
    _ => '$count, on ${on.length} workspaces',
  };
}

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

/// What each page of the server says it is set to, by page; null for one that is not set up.
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
    SettingsPage.chats: 'Browse and export',
    SettingsPage.embeds: switch (system.embeds) {
      final embeds? => _widgets(embeds),
      null => '',
    },
    SettingsPage.privacy: switch (values['DisableTelemetry']) {
      true || 'true' => 'Anonymous telemetry off',
      _ => 'Anonymous telemetry on',
    },
  };
}

/// The pages beside the list, in the groups the Server page puts them under.
const _groups = [
  (
    'Answers',
    [SettingsPage.chatModel, SettingsPage.searchModel, SettingsPage.storage],
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
        final summaries = _summaries(scope.system, values);
        return widget.phone
            ? _narrow(context, summaries)
            : _wide(context, summaries);
      },
    );
  }

  /// A phone's page: four groups of rows, then a way to AnythingLLM's web page.
  Widget _narrow(BuildContext context, Map<SettingsPage, String?> summaries) {
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

  /// The page beside the list: the pages in three groups, then the folds.
  Widget _wide(BuildContext context, Map<SettingsPage, String?> summaries) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    Widget go(SettingsPage page, String? value) => _SummaryRow(
      page.label,
      value ?? '',
      onTap: () => shell.showSettingsPage(page),
    );
    final notSetUp = [
      for (final (_, pages) in _groups)
        for (final page in pages)
          if (summaries[page] == null) page,
    ];
    final host = scope.settings.connection?.uri.host;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 18,
      children: [
        for (final (label, pages) in _groups)
          if (pages.where((p) => summaries[p] != null).toList() case final shown
              when shown.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                SectionLabel(label),
                FieldCard([
                  for (final page in shown) go(page, summaries[page]),
                ]),
              ],
            ),
        if (notSetUp.isNotEmpty)
          _Folded('Not set up (${notSetUp.length})', [
            for (final page in notSetUp) go(page, 'Set up'),
          ]),
        _Folded(
          'In AnythingLLM\'s web page (${webPages.length})',
          [
            for (final web in webPages)
              _SummaryRow(
                web.label,
                'Opens in the browser',
                out: true,
                onTap: () => openServerPage(context),
              ),
          ],
          note: host == null
              ? null
              : 'These open $host in the browser. They are rarely changed, and changing '
                    'them needs the server password.',
        ),
        _Folded('Advanced', [
          go(SettingsPage.json, 'Every setting, as the server stores it'),
        ]),
      ],
    );
  }
}

/// A fold, closed at first, with rows in a card under it and a line under that once opened.
class _Folded extends StatefulWidget {
  const _Folded(this.label, this.rows, {this.note});

  final String label;
  final List<Widget> rows;
  final String? note;

  @override
  State<_Folded> createState() => _FoldedState();
}

class _FoldedState extends State<_Folded> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 8,
    children: [
      Fold(
        label: widget.label,
        open: _open,
        onToggle: () => setState(() => _open = !_open),
      ),
      if (_open) ...[
        FieldCard(widget.rows),
        if (widget.note case final note?) HelpText(note),
      ],
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
