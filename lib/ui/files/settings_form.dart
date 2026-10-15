import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../app_scope.dart';
import '../layout.dart';
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
  static const _refusalKey = 'queryRefusalResponse';

  late final Map<String, Object?> _saved;
  late final TextEditingController _refusal;
  late String? _mode;
  bool _saving = false;

  /// Whether the model picker shows.
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    final detail = AppScope.of(context).files.detail(widget.slug);
    _saved = {...?detail?.settings?.values};
    _refusal = TextEditingController(text: _show(_saved[_refusalKey]));
    _mode = _saved['chatMode'] as String?;
  }

  @override
  void dispose() {
    _refusal.dispose();
    super.dispose();
  }

  static String _show(Object? value) => value == null ? '' : '$value';

  /// The two settings the form edits, by column. A field left as the server had it keeps the
  /// server's value, even `""` or one with spaces around it, so it is not sent.
  Map<String, Object?> get _values {
    final text = _refusal.text.trim();
    return {
      'chatMode': _mode,
      _refusalKey: text == _show(_saved[_refusalKey]).trim()
          ? _saved[_refusalKey]
          : text.isEmpty
          ? null
          : text,
    };
  }

  bool get _dirty =>
      _values.entries.any((entry) => entry.value != _saved[entry.key]);

  Future<void> _save() async {
    setState(() => _saving = true);
    await AppScope.of(context).files.save(jsonEncode(_values));
    if (mounted) setState(() => _saving = false);
  }

  void _revert() => setState(() {
    _refusal.text = _show(_saved[_refusalKey]);
    _mode = _saved['chatMode'] as String?;
  });

  @override
  Widget build(BuildContext context) {
    final dirty = _dirty;
    // The buttons show only once something has changed, as the design canvas draws the page at
    // rest.
    return _form(
      context,
      dirty || _saving
          ? ActionRow(
              even: true,
              saveRevertButtons(
                dirty: dirty,
                saving: _saving,
                onSave: _save,
                onRevert: _revert,
              ),
            )
          : null,
    );
  }

  /// The three settings, then [buttons], when there are any.
  Widget _form(BuildContext context, Widget? buttons) {
    final scope = AppScope.of(context);
    final workspace = scope.chat.active?.name ?? 'this workspace';
    return ListView(
      padding: Sizes.pagePadding,
      children: [
        const CardHeading('Answer from', top: 0),
        Semantics(
          container: true,
          label: 'Answer from',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              for (final mode in ChatMode.values)
                RadioCard(
                  title: mode.title,
                  about: mode.detail,
                  selected: _mode == mode.name,
                  onTap: () => setState(() => _mode = mode.name),
                ),
            ],
          ),
        ),
        const CardHeading('Model'),
        ListenableBuilder(
          listenable: Listenable.merge([scope.sources, scope.system]),
          builder: (context, _) {
            // The system's model names the row while the workspace has none of its own.
            scope.system.wantSettingsOnce();
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
        const CardHeading('When the files do not cover it'),
        AppField(
          controller: _refusal,
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
        if (buttons != null) ...[const SizedBox(height: 20), buttons],
      ],
    );
  }
}
