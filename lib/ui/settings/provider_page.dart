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

/// A page of the server's providers: each of [settings]' choosers in its own card, and the
/// settings of the provider chosen in a card under it, saved together to the server's `.env`.
/// [before] and [after] go above and below them, [lead] are rows above the first chooser in
/// its card, and [fieldsNote] is a line between a chooser and its provider's settings.
class ProviderPage extends StatelessWidget {
  const ProviderPage(
    this.settings, {
    super.key,
    this.before = const [],
    this.after = const [],
    this.lead = const [],
    this.fieldsNote,
  });

  final List<ProviderSetting> settings;
  final List<Widget> before;
  final List<Widget> after;
  final List<Widget> lead;
  final String? fieldsNote;

  @override
  Widget build(BuildContext context) => ServerSettings(
    before: before,
    after: after,
    builder: (values, revision) => _ProviderForm(
      key: ValueKey(revision),
      settings: settings,
      values: values,
      lead: lead,
      fieldsNote: fieldsNote,
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
    required this.lead,
    required this.fieldsNote,
  });

  final List<ProviderSetting> settings;
  final Map<String, Object?> values;
  final List<Widget> lead;
  final String? fieldsNote;

  @override
  State<_ProviderForm> createState() => _ProviderFormState();
}

class _ProviderFormState extends State<_ProviderForm> with SettingsSaving {
  late final Map<String, String> _chosen = {
    for (final s in widget.settings) s.chooser: _saved(s.chooser),
  };
  final _text = <String, TextEditingController>{};

  /// Whether the fields that are rarely changed show.
  bool _advancedOpen = false;

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
    final help = s.recommended == null || recommended ? s.help : '';
    if (!s.writable) {
      return ReadOnlyRow(label: s.label, help: help, value: s.labelOf(value));
    }
    return FieldRow(
      label: s.label,
      help: help,
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
            const AppBadge('Saved, not shown', kind: BadgeKind.ok),
            AppButton(
              'Change',
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
      control: secret
          ? SecretField(
              controller: _controller(field),
              label: field.label,
              hint: 'Not set',
              onChanged: (_) => setState(() {}),
            )
          : AppField(
              controller: _controller(field),
              label: field.label,
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
        for (final (i, (s, of)) in shown.indexed) ...[
          FieldCard([if (i == 0) ...widget.lead, _chooser(s, saving)]),
          if (of.where((f) => !f.advanced).toList() case final main
              when main.isNotEmpty) ...[
            if (widget.fieldsNote case final note?) PageNote(note),
            FieldCard([for (final field in main) _field(field, saving)]),
          ],
        ],
        if (fields.where((f) => f.advanced).toList() case final rare
            when rare.isNotEmpty) ...[
          Fold(
            label: 'Advanced (${rare.length})',
            open: _advancedOpen,
            onToggle: () => setState(() => _advancedOpen = !_advancedOpen),
          ),
          if (_advancedOpen)
            FieldCard([for (final field in rare) _field(field, saving)]),
        ],
        if (confirmBox(() => _draft(fields)) case final box?)
          box
        else if (widget.settings.any((s) => s.writable) || fields.isNotEmpty)
          ActionRow(
            alignment: WrapAlignment.start,
            saveRevertButtons(
              dirty: dirty,
              saving: saving,
              onSave: () => save(_draft(fields)),
              onRevert: _revert,
              saveFirst: true,
            ),
          ),
      ],
    );
  }
}

/// How many passages the server's database holds, across every workspace, read when it shows:
/// a row of a [FieldCard].
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
      builder: (context, _) => ReadOnlyRow(
        label: 'Stored passages',
        value: switch (system) {
          SystemController(problem: final problem?) =>
            '${problem.title}: ${problem.text}',
          SystemController(vectors: final count?) =>
            '${grouped(count)} across every workspace',
          _ => 'Counting…',
        },
      ),
    );
  }
}

/// The warning over the document search model: a change clears every document's searchable
/// copy, with how many passages that is once the server has counted them.
class SearchModelWarning extends StatefulWidget {
  const SearchModelWarning({super.key});

  @override
  State<SearchModelWarning> createState() => _SearchModelWarningState();
}

class _SearchModelWarningState extends State<SearchModelWarning> {
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
      builder: (context, _) {
        final count = system.vectors;
        final all = count == null
            ? ''
            : ', ${plural(count, 'passage', 'passages')} in all';
        return PageWarning(
          'Changing this model clears the searchable copy of every document$all. Each '
          'document has to be prepared again before answers can use it.',
        );
      },
    );
  }
}
