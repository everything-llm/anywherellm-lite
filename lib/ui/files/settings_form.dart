import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../../core/server_models.dart';
import '../app_scope.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../chat/model_picker.dart';
import '../widgets/fields.dart';
import '../widgets/phone_page.dart';
import '../widgets/radio_card.dart';
import '../settings/rows.dart';

/// A workspace's answer settings as a form, in place of `settings.json`, in the composer's words:
/// Answer from as a card for each mode, the chat model, which opens the [ModelPicker], and what
/// Files only says when the files do not cover a question. The rest is kept as the server has it.
/// Saving sends only what changed, through the same checks as `settings.json`. Its key changes
/// each time the settings are read afresh, which drops the draft.
class SettingsForm extends StatefulWidget {
  const SettingsForm({super.key, required this.slug});

  final String slug;

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

  /// Whether the model picker shows.
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
    if (problems.isNotEmpty) return;
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
  });

  @override
  Widget build(BuildContext context) {
    final dirty = _dirty;
    // The buttons show only once something has changed, as the design canvas draws the page at
    // rest.
    return _form(
      context,
      dirty || _saving
          ? ActionRow(even: true, [
              AppButton(
                'Revert',
                onPressed: dirty && !_saving ? _revert : null,
              ),
              AppButton(
                _saving ? 'Saving…' : 'Save',
                primary: true,
                onPressed: dirty && !_saving ? _save : null,
              ),
            ])
          : null,
    );
  }

  /// The three settings, then [buttons], when there are any.
  Widget _form(BuildContext context, Widget? buttons) {
    final scope = AppScope.of(context);
    final workspace = scope.chat.active?.name ?? 'this workspace';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        const SizedBox(height: 18),
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
          '$workspace. Chat history, temperature and document search stay as the server has them.',
        ),
        if (buttons != null) ...[const SizedBox(height: 16), buttons],
      ],
    );
  }
}
