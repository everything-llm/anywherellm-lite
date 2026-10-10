import 'package:flutter/material.dart';

import '../../core/system_settings.dart';
import '../app_scope.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import 'rows.dart';
import 'server_settings.dart';

/// The server's settings as JSON, with no secret in it, for those no other page shows. A key the
/// server has no value for may be added; saving writes them to the server's `.env`.
class JsonPage extends StatelessWidget {
  const JsonPage({super.key});

  @override
  Widget build(BuildContext context) => ServerSettings(
    before: const [
      PageNote(
        'Keys and passwords are left out; add one by its name to replace it. Only the '
        'settings the server takes from the app are written.',
      ),
    ],
    builder: (values, revision) =>
        _JsonForm(key: ValueKey(revision), settings: values),
  );
}

class _JsonForm extends StatefulWidget {
  const _JsonForm({super.key, required this.settings});

  final Map<String, Object?> settings;

  @override
  State<_JsonForm> createState() => _JsonFormState();
}

class _JsonFormState extends State<_JsonForm> with SettingsSaving {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Semantics(
          label: 'system.json',
          textField: true,
          child: TextField(
            controller: _draft,
            minLines: 14,
            maxLines: 24,
            autocorrect: false,
            enableSuggestions: false,
            style: Type.mono(13, color: t.ink, height: 1.5),
            cursorColor: t.accent,
            decoration: editorDecoration(context, t.bg),
          ),
        ),
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
    );
  }
}
