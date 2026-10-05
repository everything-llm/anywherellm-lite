import 'package:flutter/material.dart';

import '../../core/connection.dart';
import '../app_scope.dart';
import '../state/settings_controller.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import 'page_frame.dart';

/// The AnythingLLM address and key: test them, save them to the keyring, or remove them.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final SettingsController _settings;
  final _url = TextEditingController();
  final _key = TextEditingController();

  /// The connection the fields were last filled from.
  Connection? _filledFrom;

  @override
  void initState() {
    super.initState();
    _settings = AppScope.of(context).settings;
    _fill();
    _settings.addListener(_follow);
  }

  @override
  void dispose() {
    _settings.removeListener(_follow);
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  void _fill() {
    _filledFrom = _settings.connection;
    _url.text = _filledFrom?.baseUrl ?? '';
    _key.text = _filledFrom?.apiKey ?? '';
  }

  /// Refills the fields when the connection in use changes under them: read from the keyring
  /// after the page opened, saved with a cleaned address, or removed.
  void _follow() {
    if (_settings.connection != _filledFrom) _fill();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        final settings = _settings;
        final testing = settings.check == ConnectionCheck.testing;
        final message = settings.message;
        final problem = settings.keyringProblem;
        return PageFrame(
          children: [
            const PageHead(
              'Settings',
              sub: 'The AnythingLLM server this app talks to. The key is kept in the system keyring.',
            ),
            NilsCard(
              children: [
                LabeledField(
                  label: 'Server address',
                  controller: _url,
                  hint: 'https://host:3001',
                  help: 'For example https://host.example.ts.net:3001',
                ),
                LabeledField(
                  label: 'API key',
                  controller: _key,
                  secret: true,
                  help: 'Created in AnythingLLM under Settings, Developer API.',
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    NilsButton(
                      testing ? 'Testing...' : 'Test connection',
                      onPressed: testing
                          ? null
                          : () => settings.test(_url.text, _key.text),
                    ),
                    NilsButton(
                      'Save',
                      primary: true,
                      onPressed: testing
                          ? null
                          : () => settings.save(_url.text, _key.text),
                    ),
                    if (settings.configured)
                      NilsButton('Remove saved key', onPressed: settings.clear),
                  ],
                ),
                if (settings.check == ConnectionCheck.failed && message != null)
                  AlertBox(
                    AlertKind.bad,
                    'Could not use these details',
                    text: message,
                  )
                else if (message != null)
                  HelpText(message, status: true),
              ],
            ),
            if (problem != null)
              AlertBox(AlertKind.bad, problem.title, text: problem.text),
          ],
        );
      },
    );
  }
}
