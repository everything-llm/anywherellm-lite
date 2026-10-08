import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../../core/server_models.dart';
import '../app_scope.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../chat/model_picker.dart';
import '../widgets/fields.dart';
import '../widgets/phone_page.dart';
import '../widgets/radio_card.dart';
import '../widgets/setting_row.dart';
import '../widgets/segmented.dart';
import '../settings/rows.dart';

/// The similarity thresholds the web UI offers, with the score each one stands for.
const similarityPresets = [
  (0, 'None'),
  (0.25, 'Low'),
  (0.5, 'Medium'),
  (0.75, 'High'),
];

/// What each chat mode does, as the web UI says it.
const _modeHelp = {
  'automatic': 'Agent uses tools on its own when the model supports them. Otherwise type @agent to use them.',
  'chat': 'Chat answers from the model and the workspace documents.',
  'query': 'Query answers only from the workspace documents.',
};

/// What each chat mode does, in the words of the composer's Answer from chip.
const _plainModeHelp =
    'The same choice as the chip in the message box. It applies to every chat in this workspace.';

/// A workspace's answer settings as a form, in place of `settings.json`. Saving sends only what
/// changed, through the same checks as the JSON editor. Its key changes each time the settings
/// are read afresh, which drops the draft.
class SettingsForm extends StatefulWidget {
  const SettingsForm({
    super.key,
    required this.slug,
    required this.onJson,
    this.plain = false,
    this.phone = false,
  });

  final String slug;

  /// Shows only what a phone does, in the composer's words: Answer from as a card for each
  /// mode, the chat model, which opens the [ModelPicker], and what Files only says when the
  /// files do not cover a question. The rest is kept as the server has it.
  final bool phone;

  /// Names the chat mode and the refusal as the Essentials view does, in the composer's words,
  /// rather than AnythingLLM's.
  final bool plain;

  /// Switches to the JSON editor.
  final VoidCallback onJson;

  @override
  State<SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<SettingsForm> {
  static const _textKeys = [
    'chatProvider',
    'chatModel',
    'agentProvider',
    'agentModel',
    'queryRefusalResponse',
    'openAiHistory',
    'openAiTemp',
    'topN',
  ];

  late final Map<String, Object?> _saved;
  late final Map<String, TextEditingController> _text;
  late String? _mode;
  late String? _search;
  late Object? _similarity;
  bool _saving = false;
  bool _checked = false;

  /// Whether the model picker shows, on a phone.
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    final detail = AppScope.of(context).files.detail(widget.slug);
    _saved = {...?detail?.settings?.values};
    _text = {
      for (final key in _textKeys)
        key: TextEditingController(text: _show(_saved[key])),
    };
    _mode = _saved['chatMode'] as String?;
    _search = _saved['vectorSearchMode'] as String?;
    _similarity = _saved['similarityThreshold'];
  }

  @override
  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  static String _show(Object? value) => value == null ? '' : '$value';

  /// The form's values by column, or the problem with each one that cannot be read.
  (Map<String, Object?>, Map<String, String>) _read() {
    final values = <String, Object?>{};
    final problems = <String, String>{};
    for (final key in _textKeys) {
      final text = _text[key]!.text.trim();
      final spec = workspaceSettingSpecs[key]!;
      // A field left as the server had it keeps the server's value, even `""` or one with
      // spaces around it, so it is not sent.
      if (text == _show(_saved[key]).trim()) {
        values[key] = _saved[key];
        continue;
      }
      if (text.isEmpty) {
        values[key] = null;
        continue;
      }
      switch (spec.type) {
        case SettingType.text:
          values[key] = text;
        case SettingType.integer:
          final whole = int.tryParse(text);
          whole == null
              ? problems[key] = 'A whole number.'
              : values[key] = whole;
        case SettingType.number:
          final number = num.tryParse(text);
          number == null ? problems[key] = 'A number.' : values[key] = number;
      }
    }
    values['chatMode'] = _mode;
    values['vectorSearchMode'] = _search;
    values['similarityThreshold'] = _similarity;
    return (values, problems);
  }

  bool get _dirty {
    final (values, problems) = _read();
    return problems.isNotEmpty ||
        values.entries.any((entry) => entry.value != _saved[entry.key]);
  }

  Future<void> _save() async {
    final (values, problems) = _read();
    if (problems.isNotEmpty) {
      setState(() => _checked = true);
      return;
    }
    setState(() => _saving = true);
    await AppScope.of(context).files.save(jsonEncode(values));
    if (mounted) setState(() => _saving = false);
  }

  void _revert() => setState(() {
    for (final key in _textKeys) {
      _text[key]!.text = _show(_saved[key]);
    }
    _mode = _saved['chatMode'] as String?;
    _search = _saved['vectorSearchMode'] as String?;
    _similarity = _saved['similarityThreshold'];
    _checked = false;
  });

  Widget _field(
    String key,
    String label,
    String help, {
    String? hint,
    TextInputType? keyboard,
    int maxLines = 1,
    String? problem,
  }) => SettingRow(
    label: label,
    help: help,
    problem: _checked ? problem : null,
    child: AppField(
      controller: _text[key]!,
      label: label,
      hint: hint,
      keyboardType: keyboard,
      maxLines: maxLines,
      onChanged: (_) => setState(() {}),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final (_, problems) = _read();
    const system = 'System default';
    final similarity = _similarity;
    final preset = similarityPresets
        .where((p) => similarity is num && p.$1 == similarity)
        .firstOrNull;
    final dirty = _dirty;
    final buttons = ActionRow([
      AppButton('Revert', onPressed: dirty && !_saving ? _revert : null),
      AppButton(
        _saving ? 'Saving…' : 'Save',
        primary: true,
        onPressed: dirty && !_saving ? _save : null,
      ),
    ]);
    if (widget.phone) return _phone(context, buttons);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Leave a field empty to use the system default.',
                        style: Type.sans(13, color: t.muted),
                      ),
                    ),
                    TextAction('doc', 'Edit as JSON', widget.onJson),
                  ],
                ),
                const SizedBox(height: 18),
                const SectionLabel('Answers'),
                const SizedBox(height: 12),
                SettingRow(
                  label: widget.plain ? 'Answer from' : 'Chat mode',
                  help: widget.plain
                      ? _plainModeHelp
                      : _modeHelp[_mode] ?? 'The workspace has no chat mode.',
                  child: Segmented<String>(
                    // AnythingLLM's own names, or the plain words of the composer's Answer
                    // from chip.
                    options: [
                      for (final m in ChatMode.values)
                        (m.name, widget.plain ? m.title : m.label),
                    ],
                    value: _mode,
                    maxLines: widget.plain ? 3 : 1,
                    onChanged: (mode) => setState(() => _mode = mode),
                  ),
                ),
                _field(
                  'openAiHistory',
                  'Chat history',
                  'How many earlier chats the model remembers. 20 is recommended.',
                  hint: system,
                  keyboard: TextInputType.number,
                  problem: problems['openAiHistory'],
                ),
                _field(
                  'openAiTemp',
                  'Temperature',
                  'Higher is more creative. Too high can make some models incoherent.',
                  hint: system,
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  problem: problems['openAiTemp'],
                ),
                _field(
                  'queryRefusalResponse',
                  widget.plain
                      ? 'When the files do not cover it'
                      : 'Query refusal response',
                  widget.plain
                      ? 'What Files only says when no document matches.'
                      : 'What Query mode says when no document matches.',
                  hint: system,
                  maxLines: 4,
                ),
                const SizedBox(height: 6),
                const SectionLabel('Model'),
                const SizedBox(height: 12),
                _field(
                  'chatProvider',
                  'LLM provider',
                  'The provider this workspace uses instead of the system one.',
                  hint: system,
                ),
                _field(
                  'chatModel',
                  'LLM model',
                  'The model, in the provider\'s own name for it.',
                  hint: system,
                ),
                _field(
                  'agentProvider',
                  'Agent provider',
                  'The provider behind @agent in this workspace.',
                  hint: system,
                ),
                _field(
                  'agentModel',
                  'Agent model',
                  'The agent\'s model, in the provider\'s own name for it.',
                  hint: system,
                ),
                const SizedBox(height: 6),
                const SectionLabel('Documents'),
                const SizedBox(height: 12),
                SettingRow(
                  label: 'Search preference',
                  help: 'Accuracy optimized re-ranks the passages. It is slower but finds more relevant ones.',
                  child: Segmented<String>(
                    options: const [
                      ('default', 'Default'),
                      ('rerank', 'Accuracy optimized'),
                    ],
                    value: _search,
                    onChanged: (mode) => setState(() => _search = mode),
                  ),
                ),
                _field(
                  'topN',
                  'Max context snippets',
                  'The most passages sent to the model per message. 4 is recommended.',
                  hint: system,
                  keyboard: TextInputType.number,
                  problem: problems['topN'],
                ),
                SettingRow(
                  label: 'Minimum relevance',
                  help: preset != null
                      ? 'How closely a passage must match the question to be used. '
                            '${preset.$2} needs a similarity score of ${preset.$1}; '
                            'AnythingLLM calls this the similarity threshold.'
                      : similarity == null
                      ? 'Using the system default.'
                      : 'Set to $similarity on the server. Pick one to replace it.',
                  child: Segmented<num>(
                    options: [
                      for (final (score, name) in similarityPresets)
                        (score, name),
                    ],
                    value: preset?.$1,
                    onChanged: (score) => setState(() => _similarity = score),
                  ),
                ),
                const SizedBox(height: 6),
                buttons,
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The phone's three settings, under their buttons' row.
  Widget _phone(BuildContext context, Widget buttons) {
    final scope = AppScope.of(context);
    final workspace = scope.chat.active?.name ?? 'this workspace';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        const SizedBox(height: 14),
        const SectionLabel('Answer from'),
        const SizedBox(height: 6),
        Semantics(
          container: true,
          label: 'Answer from',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final mode in ChatMode.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: RadioCard(
                    title: mode.title,
                    about: mode.detail,
                    selected: _mode == mode.name,
                    onTap: () => setState(() => _mode = mode.name),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const SectionLabel('Model'),
        const SizedBox(height: 6),
        ListenableBuilder(
          listenable: Listenable.merge([scope.sources, scope.system]),
          builder: (context, _) {
            final own = scope.sources.chatModel;
            final model = workspaceModel(scope);
            return FieldCard([
              NavRow(
                title: 'Chat model',
                about:
                    own ??
                    (model == 'Chat model' ? null : 'The server\'s: $model'),
                onTap: () => setState(() => _picking = !_picking),
              ),
            ]);
          },
        ),
        if (_picking) ...[
          const SizedBox(height: 8),
          ModelPicker(onClose: () => setState(() => _picking = false)),
        ],
        const SizedBox(height: 18),
        const SectionLabel('When the files do not cover it'),
        const SizedBox(height: 6),
        AppField(
          controller: _text['queryRefusalResponse']!,
          label: 'When the files do not cover it',
          hint: 'System default',
          maxLines: 3,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        HelpText(
          'What Files only says when no document matches. These apply to every chat in '
          '$workspace. Chat history, temperature and document search are in the desktop app.',
        ),
        const SizedBox(height: 16),
        buttons,
      ],
    );
  }
}
