import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/connection.dart';
import '../../core/ports.dart';
import '../../core/prefs.dart';
import '../app_scope.dart';
import '../state/settings_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';
import '../widgets/segmented.dart';
import '../widgets/qr_mark.dart';
import 'model_card.dart';

/// The AnythingLLM address and key, and how answers are made. Drawn over the app by the shell.
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Settings',
      child: FocusScope(
        autofocus: true,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: t.panel2,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: t.shadow.withValues(alpha: 0.35),
                blurRadius: 60,
                spreadRadius: -12,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Settings',
                          style: Type.serif(30, color: t.ink),
                        ),
                      ),
                    ),
                    AppButton(
                      'Done',
                      primary: true,
                      onPressed: scope.shell.closeSettings,
                    ),
                  ],
                ),
                const _Section('AnythingLLM API'),
                const _KeyCard(),
                const _PasswordCard(),
                const _ModelSection(),
                const _Section('Appearance'),
                const _AppearanceCard(),
                const SizedBox(height: 22),
                Text(
                  'Your questions and the relevant passages from your files are sent to '
                  'AnythingLLM. Search and storage are handled there.',
                  style: Type.sans(12.5, color: t.muted, height: 1.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 8),
    child: SectionLabel(title),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: children,
      ),
    );
  }
}

/// The server's chat provider and model, once a server is saved.
class _ModelSection extends StatelessWidget {
  const _ModelSection();

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        // A password saved or forgotten is the same server, so the card keeps its draft.
        final server = settings.connection?.withPassword(null);
        if (server == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Section('Chat model'),
            _Card(children: [ModelCard(key: ValueKey(server))]),
          ],
        );
      },
    );
  }
}

/// The theme, and the size of a chat's text.
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final prefs = AppScope.of(context).prefs;
    Widget row(String label, Widget control) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text(
          label,
          style: Type.sans(14.5, weight: FontWeight.w500, color: t.ink),
        ),
        control,
      ],
    );
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => _Card(
        children: [
          row(
            'Theme',
            Segmented<ThemePref>(
              options: const [
                (ThemePref.system, 'System'),
                (ThemePref.light, 'Light'),
                (ThemePref.dark, 'Dark'),
              ],
              value: prefs.prefs.theme,
              onChanged: prefs.setTheme,
            ),
          ),
          row(
            'Chat text size',
            Segmented<TextSize>(
              options: const [
                (TextSize.small, 'Small'),
                (TextSize.normal, 'Normal'),
                (TextSize.large, 'Large'),
              ],
              value: prefs.prefs.textSize,
              onChanged: prefs.setTextSize,
            ),
          ),
          if (prefs.problem case final problem?)
            HelpText('${problem.title}. ${problem.text}', status: true),
        ],
      ),
    );
  }
}

/// The address and key: saved, replaced or forgotten, shown as a QR code for a phone, or read
/// from one. A key is saved only once the server takes it.
class _KeyCard extends StatefulWidget {
  const _KeyCard();

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
        final pasteKey = _pasteKey || _settings.needsKey;
        return _Card(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
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
                            ? 'Saved in your system keyring. Never shown.'
                            : pasteKey
                            ? 'Create a key in AnythingLLM under Settings → Developer API, then paste it here.'
                            : 'Sign in with the password AnythingLLM\'s web page asks for. The app makes its own developer key.',
                        style: Type.sans(12.5, color: t.muted, height: 1.45),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AppBadge(
                  set ? 'Set' : 'Missing',
                  kind: set ? BadgeKind.ok : BadgeKind.warn,
                ),
              ],
            ),
            if (set && !_replacing)
              Text(connection.baseUrl, style: Type.mono(12.5, color: t.muted)),
            if (set)
              Wrap(
                spacing: 8,
                children: [
                  AppButton(
                    _replacing ? 'Cancel' : 'Replace',
                    onPressed: () => setState(() {
                      _replacing = !_replacing;
                      _scanning = false;
                    }),
                  ),
                  if (!_replacing)
                    AppButton(
                      _showCode ? 'Hide QR code' : 'Show QR code',
                      onPressed: () => setState(() => _showCode = !_showCode),
                    ),
                  AppButton(
                    _confirmForget ? 'Delete it?' : 'Forget',
                    onPressed: _forget,
                  ),
                ],
              ),
            if (set && !_replacing && _showCode) _PairingCode(connection),
            if (_scanner case final scan? when editing && _scanning) ...[
              scan(_scanned),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  'Cancel',
                  onPressed: () => setState(() => _scanning = false),
                ),
              ),
            ],
            if (editing && !_scanning) ...[
              AppField(
                controller: _url,
                label: 'AnythingLLM server address',
                hint: _example,
                keyboardType: TextInputType.url,
                autofillHints: const [AutofillHints.url],
              ),
              if (pasteKey)
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppButton(
                    saving
                        ? 'Checking…'
                        : pasteKey
                        ? 'Save key'
                        : 'Sign in',
                    primary: true,
                    onPressed: saving
                        ? null
                        : pasteKey
                        ? _save
                        : _signIn,
                  ),
                  if (!_settings.needsKey)
                    AppButton(
                      pasteKey ? 'Use password' : 'Paste a key',
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
                ],
              ),
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

/// The server's password, under the key, once the server has said it has one or a password is
/// saved. It signs in to the web UI's own routes, which the key does not open.
class _PasswordCard extends StatefulWidget {
  const _PasswordCard();

  @override
  State<_PasswordCard> createState() => _PasswordCardState();
}

class _PasswordCardState extends State<_PasswordCard> {
  late final SettingsController _settings = AppScope.of(context).settings;
  final _password = TextEditingController();
  bool _replacing = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await _settings.savePassword(_password.text);
    if (mounted && saved) {
      setState(() {
        _password.clear();
        _replacing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _settings,
    builder: (context, _) {
      final connection = _settings.connection;
      final auth = _settings.auth;
      final set = connection?.password != null;
      if (connection == null ||
          (!set &&
              auth != ServerAuth.password &&
              auth != ServerAuth.multiUser)) {
        return const SizedBox.shrink();
      }
      final t = Tokens.of(context);
      final checking = _settings.checkingPassword;
      final editing = !set || _replacing;
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: _Card(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        'Server password',
                        style: Type.sans(
                          14.5,
                          weight: FontWeight.w500,
                          color: t.ink,
                        ),
                      ),
                      Text(
                        auth == ServerAuth.multiUser && !set
                            ? 'This server has several users. Signing in with a user name is not supported, so its own commands, feedback, and Retry and Edit that replace the old exchange stay off.'
                            : set
                            ? 'Saved in your system keyring. Never shown.'
                            : 'Optional. This server has a password. With it, the app lists the server\'s own commands, marks answers good or bad, and Retry and Edit replace the old exchange.',
                        style: Type.sans(12.5, color: t.muted, height: 1.45),
                      ),
                    ],
                  ),
                ),
                if (auth != ServerAuth.multiUser || set) ...[
                  const SizedBox(width: 10),
                  AppBadge(
                    set ? 'Set' : 'Not set',
                    kind: set ? BadgeKind.ok : BadgeKind.accent,
                  ),
                ],
              ],
            ),
            if (set)
              Wrap(
                spacing: 8,
                children: [
                  AppButton(
                    _replacing ? 'Cancel' : 'Replace',
                    onPressed: () => setState(() => _replacing = !_replacing),
                  ),
                  AppButton('Forget', onPressed: _settings.forgetPassword),
                ],
              ),
            if (editing && auth != ServerAuth.multiUser) ...[
              AppField(
                controller: _password,
                label: 'Server password',
                hint: 'The password AnythingLLM\'s web page asks for',
                obscure: true,
                keyboardType: TextInputType.visiblePassword,
                onSubmitted: (_) => checking ? null : _save(),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  checking ? 'Checking…' : 'Save password',
                  primary: true,
                  onPressed: checking ? null : _save,
                ),
              ),
            ],
            if (_settings.passwordMessage case final message?)
              HelpText(message, status: true),
          ],
        ),
      );
    },
  );
}

/// [connection] as a QR code a phone scans in its own Settings, with why the phone cannot use it
/// when it cannot.
class _PairingCode extends StatelessWidget {
  const _PairingCode(this.connection);

  final Connection connection;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: QrMark(
                pairingCode(connection),
                label: 'QR code with the server address and key',
              ),
            ),
          ),
        ),
        Text(
          'Anyone who sees this code can use your key. Scan it in AnywhereLLM on your phone: '
          'Settings, Scan QR code.',
          style: Type.sans(12.5, color: t.muted, height: 1.45),
        ),
        if (pairingProblem(connection) case final problem?)
          AlertBox(
            AlertKind.warn,
            'Your phone cannot use this address',
            text: problem,
          ),
      ],
    );
  }
}
