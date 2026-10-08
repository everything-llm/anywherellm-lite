import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/connection.dart';
import '../../core/ports.dart';
import '../app_scope.dart';
import '../state/settings_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';
import 'pairing_code.dart';
import 'password_card.dart';
import 'rows.dart';

/// How this device reaches the server: the address and key, the server's password, and what
/// the server and the relay say. The server reads Connected once Test connection passes here,
/// until the page closes or the connection changes or fails a test.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  /// Whether Test connection was asked on this page.
  bool _tested = false;

  void _test() {
    setState(() => _tested = true);
    AppScope.of(context).settings.testSaved();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _KeyCard(tested: _tested),
      const PasswordCard(),
      _ServerStatus(onTest: _test),
    ],
  );
}

/// The relay and how the server signs in, and a test of the saved connection, once one is saved.
class _ServerStatus extends StatefulWidget {
  const _ServerStatus({required this.onTest});

  final VoidCallback onTest;

  @override
  State<_ServerStatus> createState() => _ServerStatusState();
}

class _ServerStatusState extends State<_ServerStatus> {
  late final SettingsController _settings = AppScope.of(context).settings;

  @override
  void initState() {
    super.initState();
    if (_settings.connection != null && _settings.relay == RelayState.unknown) {
      unawaited(_settings.readRelay());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _settings,
    builder: (context, _) {
      if (_settings.connection == null) return const SizedBox.shrink();
      final testing = _settings.check == ConnectionCheck.testing;
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 20,
          children: [
            FieldCard([
              ReadOnlyRow(
                label: 'Background answers',
                help: 'Provided by the everythingllm relay on the server.',
                value: switch (_settings.relay) {
                  RelayState.found => 'Available. Answers keep running after the app lets go of them.',
                  RelayState.absent =>
                    'Not available. Answers come straight from AnythingLLM.',
                  RelayState.unreachable => 'Could not check.',
                  RelayState.unknown => 'Checking…',
                },
              ),
              ReadOnlyRow(
                label: 'Server',
                value: switch (_settings.auth) {
                  ServerAuth.none => 'AnythingLLM, single user, no password',
                  ServerAuth.password =>
                    'AnythingLLM, single user, password on',
                  ServerAuth.multiUser => 'AnythingLLM, several users',
                  null => 'Not known yet',
                },
              ),
            ]),
            PageActions([
              AppButton(
                testing ? 'Testing…' : 'Test connection',
                onPressed: testing ? null : widget.onTest,
              ),
            ]),
          ],
        ),
      );
    },
  );
}

/// The address and key: saved, replaced or forgotten, shown as a QR code for a phone, or read
/// from one. A key is saved only once the server takes it.
class _KeyCard extends StatefulWidget {
  const _KeyCard({required this.tested});

  /// Whether Test connection was asked on this page, so a pass reads Connected.
  final bool tested;

  @override
  State<_KeyCard> createState() => _KeyCardState();
}

class _KeyCardState extends State<_KeyCard> {
  late final SettingsController _settings = AppScope.of(context).settings;
  late final CodeScanner? _scanner = AppScope.of(context).scanner;
  final _url = TextEditingController();
  final _key = TextEditingController();
  final _password = TextEditingController();
  bool _replacing = false;

  /// Whether the form takes a pasted developer key instead of the server's password.
  bool _pasteKey = false;
  bool _confirmForget = false;
  bool _showCode = false;
  bool _scanning = false;

  /// Why the last scanned code could not be used.
  String? _scanProblem;
  Timer? _forgetTimer;

  /// The address the field shows as an example, and starts with where http is allowed.
  String get _example => _settings.allowHttp
      ? 'http://localhost:3001'
      : 'https://host.example.ts.net:3001';

  @override
  void initState() {
    super.initState();
    _url.text =
        _settings.connection?.baseUrl ?? (_settings.allowHttp ? _example : '');
    // The server may have been out of reach when the app started.
    if (_settings.connection != null && _settings.auth == null) {
      unawaited(_settings.readAuth());
    }
  }

  @override
  void dispose() {
    _forgetTimer?.cancel();
    _url.dispose();
    _key.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await _settings.connect(_url.text, _key.text);
    if (mounted && saved) {
      setState(() {
        _key.clear();
        _replacing = false;
      });
    }
  }

  Future<void> _signIn() async {
    final saved = await _settings.signIn(_url.text, _password.text);
    // A server with several users gives no key this way, so the form takes one.
    if (mounted && _settings.needsKey) setState(() => _pasteKey = true);
    if (mounted && saved) {
      setState(() {
        _password.clear();
        _replacing = false;
      });
    }
  }

  /// Uses a scanned [code] as if its address and key had been typed, and connects with them.
  Future<void> _scanned(String code) async {
    final Connection connection;
    try {
      connection = parsePairingCode(code);
    } on ApiException catch (error) {
      setState(() {
        _scanning = false;
        _scanProblem = error.message;
      });
      return;
    }
    setState(() {
      _scanning = false;
      _scanProblem = null;
      // A key the server refuses then shows in its field, under why.
      _pasteKey = true;
      _url.text = connection.baseUrl;
      _key.text = connection.apiKey;
    });
    await _save();
  }

  Future<void> _forget() async {
    if (!_confirmForget) {
      setState(() => _confirmForget = true);
      _forgetTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _confirmForget = false);
      });
      return;
    }
    _forgetTimer?.cancel();
    await _settings.clear();
    if (mounted) setState(() => _confirmForget = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        final connection = _settings.connection;
        final set = connection != null;
        final editing = !set || _replacing;
        final saving = _settings.check == ConnectionCheck.testing;
        return PanelCard(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AnythingLLM server',
                        style: Type.sans(
                          14.5,
                          weight: FontWeight.w500,
                          color: t.ink,
                        ),
                      ),
                      Text(
                        set
                            ? 'The address is shown below. The key is stored in this device\'s keyring and never shown.'
                            : _pasteKey
                            ? 'Create a key in AnythingLLM under Settings → Developer API, then paste it here.'
                            : 'Sign in with the password AnythingLLM\'s web page asks for. The app makes its own developer key.',
                        style: Type.sans(12.5, color: t.muted, height: 1.45),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AppBadge(
                  !set
                      ? 'Missing'
                      : widget.tested && _settings.check == ConnectionCheck.ok
                      ? 'Connected'
                      : 'Saved',
                  kind: set ? BadgeKind.ok : BadgeKind.warn,
                ),
              ],
            ),
            if (set && !_replacing)
              Text(connection.baseUrl, style: Type.mono(12.5, color: t.muted)),
            if (set)
              ActionRow([
                AppButton(
                  _replacing ? 'Cancel' : 'Edit connection',
                  onPressed: () => setState(() {
                    _replacing = !_replacing;
                    _scanning = false;
                  }),
                ),
                if (!_replacing)
                  AppButton(
                    _showCode ? 'Hide the code' : 'Connect a phone',
                    onPressed: () => setState(() => _showCode = !_showCode),
                  ),
                AppButton(
                  _confirmForget ? 'Really forget it?' : 'Forget this server',
                  onPressed: _forget,
                ),
              ]),
            if (set && !_replacing && _showCode) PairingCode(connection),
            if (_scanner case final scan? when editing && _scanning) ...[
              scan(_scanned),
              ActionRow([
                AppButton(
                  'Cancel',
                  onPressed: () => setState(() => _scanning = false),
                ),
              ]),
            ],
            if (editing && !_scanning) ...[
              AppField(
                controller: _url,
                label: 'AnythingLLM server address',
                hint: _example,
                keyboardType: TextInputType.url,
                autofillHints: const [AutofillHints.url],
              ),
              if (_pasteKey)
                AppField(
                  controller: _key,
                  label: 'AnythingLLM developer API key',
                  hint: 'Paste the AnythingLLM API key',
                  obscure: true,
                  // Not a password: AppField leaves it out of autofill, so no saved login is
                  // offered for it.
                  keyboardType: TextInputType.visiblePassword,
                )
              else
                AppField(
                  controller: _password,
                  label: 'Server password',
                  hint: 'Leave it empty if the server has none',
                  obscure: true,
                  keyboardType: TextInputType.visiblePassword,
                  onSubmitted: (_) => saving ? null : _signIn(),
                ),
              ActionRow([
                AppButton(
                  saving
                      ? 'Checking…'
                      : _pasteKey
                      ? 'Save key'
                      : 'Sign in',
                  primary: true,
                  onPressed: saving
                      ? null
                      : _pasteKey
                      ? _save
                      : _signIn,
                ),
                AppButton(
                  _pasteKey ? 'Use password' : 'Paste a key',
                  onPressed: saving
                      ? null
                      : () => setState(() => _pasteKey = !_pasteKey),
                ),
                if (_scanner != null)
                  AppButton(
                    'Scan QR code',
                    onPressed: saving
                        ? null
                        : () => setState(() {
                            _scanning = true;
                            _scanProblem = null;
                          }),
                  ),
              ]),
            ],
            if (_scanProblem case final problem?)
              HelpText(problem, status: true),
            if (_settings.message case final message?)
              HelpText(message, status: true),
            if (_settings.keyringProblem case final problem?)
              AlertBox(AlertKind.warn, problem.title, text: problem.text),
          ],
        );
      },
    );
  }
}
