import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/system_settings.dart';
import '../app_scope.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/setting_row.dart';

/// The server's chat provider and that provider's model, which every workspace uses unless its
/// own settings name another. Saving writes them to the server's `.env`, as `system.json` does.
/// Its key is the server, so another server reads its settings afresh.
class ModelCard extends StatefulWidget {
  const ModelCard({super.key});

  @override
  State<ModelCard> createState() => _ModelCardState();
}

class _ModelCardState extends State<ModelCard> {
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            if (settings != null)
              _ModelForm(
                key: ValueKey(system.settingsRevision),
                settings: settings,
              )
            else if (problem == null)
              const HelpText('Reading the server\'s model…', status: true),
            if (problem != null)
              AlertBox(AlertKind.bad, problem.title, text: problem.text),
          ],
        );
      },
    );
  }
}

/// The provider and model as the server had them when [settings] was read. Its key changes
/// each time they are read afresh, which drops the draft.
class _ModelForm extends StatefulWidget {
  const _ModelForm({super.key, required this.settings});

  final Map<String, Object?> settings;

  @override
  State<_ModelForm> createState() => _ModelFormState();
}

class _ModelFormState extends State<_ModelForm> {
  late final String _savedProvider = _text(widget.settings['LLMProvider']);
  late String _provider = _savedProvider;
  late final _model = TextEditingController(text: _savedModel(_provider));

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  static String _text(Object? value) => value == null ? '' : '$value';

  /// The model the server has for [provider], or empty when it has none or no model setting.
  String _savedModel(String provider) =>
      _text(widget.settings[chatModelKeys[provider]]);

  bool get _dirty =>
      _provider != _savedProvider ||
      (chatModelKeys.containsKey(_provider) &&
          _model.text.trim() != _savedModel(_provider));

  /// The provider and its model as the JSON a save sends.
  String _draft() => jsonEncode({
    'LLMProvider': _provider,
    ?chatModelKeys[_provider]: _model.text.trim(),
  });

  void _choose(String? provider) {
    if (provider == null || provider == _provider) return;
    setState(() {
      _provider = provider;
      _model.text = _savedModel(provider);
    });
  }

  void _revert() => setState(() {
    _provider = _savedProvider;
    _model.text = _savedModel(_provider);
  });

  @override
  Widget build(BuildContext context) {
    final system = AppScope.of(context).system;
    final saving = system.saving;
    final dirty = _dirty;
    // A provider newer than the app's list still shows, and is kept unless another is picked.
    final choices = [
      ...systemChoices['LLMProvider']!,
      if (_savedProvider.isNotEmpty &&
          !systemChoices['LLMProvider']!.contains(_savedProvider))
        _savedProvider,
    ];
    final modelKey = chatModelKeys[_provider];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        SettingRow(
          gap: 0,
          label: 'Provider',
          help: _provider == _savedProvider
              ? 'Every workspace uses it unless its own settings name another.'
              : 'Its key or address, if it needs one, is set in Files under /settings/system.json.',
          child: Semantics(
            label: 'Provider',
            child: AppSelect(
              value: _provider,
              choices: choices,
              onChanged: saving ? null : _choose,
            ),
          ),
        ),
        if (modelKey != null)
          SettingRow(
            gap: 0,
            label: 'Model',
            help: 'The provider\'s own name for it. Saved as $modelKey.',
            child: AppField(
              controller: _model,
              label: 'Model',
              hint: 'The provider\'s name for the model',
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) =>
                  dirty && !saving ? system.saveSettings(_draft()) : null,
            ),
          )
        else if (_provider.isNotEmpty)
          const HelpText('This provider picks its own model.'),
        ActionRow([
          AppButton('Revert', onPressed: dirty && !saving ? _revert : null),
          AppButton(
            saving ? 'Saving…' : 'Save model',
            primary: true,
            onPressed: dirty && !saving
                ? () => system.saveSettings(_draft())
                : null,
          ),
        ]),
      ],
    );
  }
}
