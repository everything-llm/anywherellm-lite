import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/system_settings.dart';
import '../app_scope.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/confirm_box.dart';
import '../widgets/fields.dart';
import '../widgets/setting_row.dart';

/// The server's `system.json`: its settings as a form by section, or as JSON when asked for.
/// Saving writes them to the server's `.env`; a change that would delete every vector asks first.
class SystemPage extends StatefulWidget {
  const SystemPage({super.key});

  @override
  State<SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends State<SystemPage> {
  @override
  void initState() {
    super.initState();
    AppScope.of(context).system.readSettings();
  }

  @override
  Widget build(BuildContext context) {
    final system = AppScope.of(context).system;
    return ListenableBuilder(
      listenable: system,
      builder: (context, _) {
        final settings = system.settings;
        final problem = system.settingsProblem;
        final notice = problem == null
            ? null
            : AlertBox(AlertKind.bad, problem.title, text: problem.text);
        if (settings == null) {
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ?notice,
              if (notice == null)
                const HelpText('Loading the settings…', status: true),
            ],
          );
        }
        final key = ValueKey(system.settingsRevision);
        return system.settingsAsJson
            ? _SystemJson(key: key, settings: settings, notice: notice)
            : _SystemForm(key: key, settings: settings, notice: notice);
      },
    );
  }
}

/// Saves [draft], asking first when it changes a setting that deletes every vector.
mixin _Saving<T extends StatefulWidget> on State<T> {
  /// The settings whose change waits for the person to confirm it, while asking.
  List<String>? confirming;

  Future<void> save(String draft) async {
    final system = AppScope.of(context).system;
    final resets = system.vectorResets(draft);
    if (resets.isNotEmpty && confirming == null) {
      setState(() => confirming = resets);
      return;
    }
    setState(() => confirming = null);
    await system.saveSettings(draft);
  }

  /// The question asked before such a change, or nothing.
  Widget? confirmBox(String Function() draft) {
    final resets = confirming;
    if (resets == null) return null;
    final count = AppScope.of(context).system.vectors;
    final vectors = count == null ? 'every vector' : 'all $count vectors';
    return ConfirmBox(
      text:
          'Changing ${resets.join(' and ')} makes the server delete $vectors it holds. '
          'Every workspace\'s documents must then be embedded again before answers can use them.',
      action: 'Change and delete',
      onCancel: () => setState(() => confirming = null),
      onConfirm: () => save(draft()),
    );
  }
}

class _SystemForm extends StatefulWidget {
  const _SystemForm({super.key, required this.settings, this.notice});

  final Map<String, Object?> settings;
  final Widget? notice;

  @override
  State<_SystemForm> createState() => _SystemFormState();
}

class _SystemFormState extends State<_SystemForm> with _Saving {
  late final List<SystemField> _fields = systemFields(widget.settings);
  late final Map<String, TextEditingController> _text = {
    for (final f in _fields)
      if (f.choices == null && !f.readOnly)
        f.key: TextEditingController(text: f.value),
  };
  late final Map<String, String> _chosen = {
    for (final f in _fields)
      if (f.choices != null) f.key: f.value,
  };

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The form's values as the JSON a save sends: every setting shown, and a secret only when a
  /// new value is typed.
  String _draft() {
    final values = <String, String>{};
    for (final f in _fields) {
      if (f.readOnly) continue;
      final value = _chosen[f.key] ?? _text[f.key]!.text.trim();
      if (f.secret && value.isEmpty) continue;
      values[f.key] = value;
    }
    return jsonEncode(values);
  }

  bool get _dirty => _fields.any(
    (f) => f.secret
        ? _text[f.key]!.text.trim().isNotEmpty
        : !f.readOnly &&
              (_chosen[f.key] ?? _text[f.key]!.text.trim()) != f.value,
  );

  void _revert() => setState(() {
    for (final f in _fields) {
      if (f.choices != null) {
        _chosen[f.key] = f.value;
      } else if (!f.readOnly) {
        _text[f.key]!.text = f.secret ? '' : f.value;
      }
    }
    confirming = null;
  });

  Widget _control(SystemField f) {
    final t = Tokens.of(context);
    if (f.readOnly) {
      return Text(f.value, style: Type.mono(13.5, color: t.ink));
    }
    if (f.choices case final choices?) {
      final value = _chosen[f.key];
      return AppSelect(
        value: value,
        choices: choices,
        onChanged: (choice) => setState(() => _chosen[f.key] = choice ?? ''),
      );
    }
    return AppField(
      controller: _text[f.key]!,
      label: f.key,
      hint: f.secret ? 'Set. Type a new one to replace it.' : null,
      obscure: f.secret,
      onChanged: (_) => setState(() {}),
    );
  }

  String _help(SystemField f) => switch (f) {
    SystemField(readOnly: true) => 'Shown, not written: switching it deletes every vector in the old database.',
    SystemField(resetsVectors: true) =>
      'Changing it deletes every vector the server holds.',
    SystemField(secret: true) => 'Never shown. Leave it empty to keep it.',
    SystemField(choices: final _?) => 'One of the values the server takes.',
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final system = AppScope.of(context).system;
    final t = Tokens.of(context);
    final dirty = _dirty;
    SystemSection? section;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextAction(
            'doc',
            'Edit as JSON',
            () => system.showSettingsAsJson(true),
          ),
        ),
        Text(
          'The server\'s own settings, written to its .env. Every workspace and every client '
          'uses them. A setting the server has no value for shows only in Edit as JSON.',
          style: Type.sans(14, color: t.muted),
        ),
        if (widget.notice case final notice?) ...[
          const SizedBox(height: 12),
          notice,
        ],
        for (final f in _fields) ...[
          if (f.section != section) ...[
            const SizedBox(height: 20),
            SectionLabel((section = f.section).label),
            const SizedBox(height: 10),
          ],
          SettingRow(label: f.key, help: _help(f), child: _control(f)),
        ],
        if (confirmBox(_draft) case final box?)
          box
        else
          ActionRow([
            AppButton(
              'Revert',
              onPressed: dirty && !system.saving ? _revert : null,
            ),
            AppButton(
              system.saving ? 'Saving…' : 'Save',
              primary: true,
              onPressed: dirty && !system.saving ? () => save(_draft()) : null,
            ),
          ]),
      ],
    );
  }
}

/// The settings as JSON, with no secret in it. A key the server has no value for may be added.
class _SystemJson extends StatefulWidget {
  const _SystemJson({super.key, required this.settings, this.notice});

  final Map<String, Object?> settings;
  final Widget? notice;

  @override
  State<_SystemJson> createState() => _SystemJsonState();
}

class _SystemJsonState extends State<_SystemJson> with _Saving {
  late final String _saved = systemText(widget.settings);
  late final _draft = TextEditingController(text: _saved);

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final system = AppScope.of(context).system;
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextAction(
              'settings',
              'Edit as a form',
              () => system.showSettingsAsJson(false),
            ),
          ),
          Text(
            'Keys and passwords are left out; add one by its name to replace it. Only the '
            'settings the server takes from the app are written.',
            style: Type.sans(13, color: t.muted),
          ),
          if (widget.notice case final notice?) ...[
            const SizedBox(height: 10),
            notice,
          ],
          const SizedBox(height: 8),
          Expanded(
            child: Semantics(
              label: 'system.json',
              textField: true,
              child: TextField(
                controller: _draft,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                autocorrect: false,
                enableSuggestions: false,
                style: Type.mono(13, color: t.ink, height: 1.5),
                cursorColor: t.accent,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: t.panel,
                  contentPadding: const EdgeInsets.all(14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: t.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: t.accent, width: 2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (confirmBox(() => _draft.text) case final box?)
            box
          else
            ListenableBuilder(
              listenable: _draft,
              builder: (context, _) {
                final dirty = _draft.text != _saved;
                return ActionRow([
                  AppButton(
                    'Revert',
                    onPressed: dirty && !system.saving
                        ? () => _draft.text = _saved
                        : null,
                  ),
                  AppButton(
                    system.saving ? 'Saving…' : 'Save',
                    primary: true,
                    onPressed: dirty && !system.saving
                        ? () => save(_draft.text)
                        : null,
                  ),
                ]);
              },
            ),
        ],
      ),
    );
  }
}
