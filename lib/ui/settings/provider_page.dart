import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/providers.dart';
import '../../core/system_settings.dart';
import '../app_scope.dart';
import '../state/system_controller.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';
import 'rows.dart';
import 'server_settings.dart';

/// A page of the server's providers: each of [settings]' choosers and the settings of the
/// provider chosen, saved together to the server's `.env`. [before] and [after] go above and
/// below them.
class ProviderPage extends StatelessWidget {
  const ProviderPage(
    this.settings, {
    super.key,
    this.before = const [],
    this.after = const [],
  });

  final List<ProviderSetting> settings;
  final List<Widget> before;
  final List<Widget> after;

  @override
  Widget build(BuildContext context) => ServerSettings(
    before: before,
    after: after,
    builder: (values, revision) => _ProviderForm(
      key: ValueKey(revision),
      settings: settings,
      values: values,
    ),
  );
}

/// The choosers and fields as the server had them in [values]. Its key changes each time they
/// are read afresh, which drops the draft.
class _ProviderForm extends StatefulWidget {
  const _ProviderForm({
    super.key,
    required this.settings,
    required this.values,
  });

  final List<ProviderSetting> settings;
  final Map<String, Object?> values;

  @override
  State<_ProviderForm> createState() => _ProviderFormState();
}

class _ProviderFormState extends State<_ProviderForm> with SettingsSaving {
  late final Map<String, String> _chosen = {
    for (final s in widget.settings) s.chooser: _saved(s.chooser),
  };
  final _text = <String, TextEditingController>{};

  /// The secrets that are set and that the person asked to replace.
  final _replacing = <String>{};

  @override
  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _saved(String key) => settingText(widget.values, key);

  /// Whether [field] is a secret, which the server shows only as whether it is set.
  static bool _secret(ProviderField field) => field.kind == FieldKind.secret;

  bool _isSet(ProviderField field) => widget.values[field.key] == true;

  /// The text [field] starts with and goes back to: what the server has, or nothing for a
  /// secret.
  String _start(ProviderField field) => _secret(field) ? '' : _saved(field.key);

  TextEditingController _controller(ProviderField field) =>
      _text[field.key] ??= TextEditingController(text: _start(field));

  /// The fields of each chosen provider, each setting once.
  List<(ProviderSetting, List<ProviderField>)> get _shown {
    final seen = <String>{};
    return [
      for (final s in widget.settings)
        (
          s,
          [
            for (final field in s.named(_chosen[s.chooser]!)?.fields ?? [])
              if (seen.add(field.key)) field,
          ],
        ),
    ];
  }

  String _value(ProviderField field) => _controller(field).text.trim();

  /// Whether a chooser or any of [fields] differs from what the server has.
  bool _dirty(Iterable<ProviderField> fields) =>
      widget.settings.any(
        (s) => s.writable && _chosen[s.chooser] != _saved(s.chooser),
      ) ||
      fields.any((f) => _value(f) != _start(f));

  /// The choosers and [fields] as the JSON a save sends; a secret only when a new one is typed.
  String _draft(Iterable<ProviderField> fields) => jsonEncode({
    for (final s in widget.settings)
      if (s.writable) s.chooser: _chosen[s.chooser],
    for (final f in fields)
      if (!_secret(f) || _value(f).isNotEmpty) f.key: _value(f),
  });

  void _revert() => setState(() {
    for (final s in widget.settings) {
      _chosen[s.chooser] = _saved(s.chooser);
    }
    for (final MapEntry(:key, value: controller) in _text.entries) {
      controller.text = _start(ProviderField(key));
    }
    _replacing.clear();
    confirming = null;
  });

  Widget _chooser(ProviderSetting s, bool saving) {
    final value = _chosen[s.chooser]!;
    final recommended = s.recommended != null && value == s.recommended;
    final tag = recommended
        ? const AppBadge('Recommended', kind: BadgeKind.accent, pill: true)
        : null;
    if (!s.writable) {
      return FieldRow(
        label: s.label,
        help: s.help,
        tag: tag,
        control: Text(s.labelOf(value), textAlign: TextAlign.end),
      );
    }
    return FieldRow(
      label: s.label,
      help: s.help,
      tag: tag,
      control: Semantics(
        label: s.label,
        child: AppSelect(
          value: value,
          choices: s.choices(_saved(s.chooser)),
          labelOf: s.labelOf,
          onChanged: saving
              ? null
              : (choice) => setState(() => _chosen[s.chooser] = choice ?? ''),
        ),
      ),
    );
  }

  Widget _field(ProviderField field, bool saving) {
    final secret = _secret(field);
    if (secret && _isSet(field) && !_replacing.contains(field.key)) {
      return FieldRow(
        label: field.label,
        help: field.help,
        control: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            const AppBadge('Set, not shown', kind: BadgeKind.ok),
            AppButton(
              'Replace',
              onPressed: saving
                  ? null
                  : () => setState(() => _replacing.add(field.key)),
            ),
          ],
        ),
      );
    }
    return FieldRow(
      label: field.label,
      help: secret ? 'Never shown once saved.' : field.help,
      control: AppField(
        controller: _controller(field),
        label: field.label,
        hint: secret ? 'Not set' : null,
        obscure: secret,
        keyboardType: field.kind == FieldKind.number
            ? TextInputType.number
            : null,
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final system = AppScope.of(context).system;
    final saving = system.saving;
    final shown = _shown;
    final fields = [for (final (_, of) in shown) ...of];
    final dirty = _dirty(fields);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 20,
      children: [
        for (final (s, of) in shown)
          FieldCard([
            _chooser(s, saving),
            for (final field in of) _field(field, saving),
          ]),
        if (confirmBox(() => _draft(fields)) case final box?)
          box
        else if (widget.settings.any((s) => s.writable) || fields.isNotEmpty)
          ActionRow([
            AppButton('Revert', onPressed: dirty && !saving ? _revert : null),
            AppButton(
              saving ? 'Saving…' : 'Save',
              primary: true,
              onPressed: dirty && !saving ? () => save(_draft(fields)) : null,
            ),
          ]),
      ],
    );
  }
}

/// How many passages the server's database holds, across every workspace, read when it shows.
class StoredPassages extends StatefulWidget {
  const StoredPassages({super.key});

  @override
  State<StoredPassages> createState() => _StoredPassagesState();
}

class _StoredPassagesState extends State<StoredPassages> {
  @override
  void initState() {
    super.initState();
    AppScope.of(context).system.readVectors();
  }

  @override
  Widget build(BuildContext context) {
    final system = AppScope.of(context).system;
    return ListenableBuilder(
      listenable: system,
      builder: (context, _) => FieldCard([
        ReadOnlyRow(
          label: 'Stored passages',
          help: 'Across every workspace. AnythingLLM calls them vectors.',
          value: switch (system) {
            SystemController(problem: final problem?) =>
              '${problem.title}: ${problem.text}',
            SystemController(vectors: final count?) => plural(
              count,
              'passage',
              'passages',
            ),
            _ => 'Counting…',
          },
        ),
      ]),
    );
  }
}
