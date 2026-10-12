import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/connection.dart';
import '../../core/ports.dart';
import '../app_scope.dart';
import '../layout.dart';
import '../state/settings_controller.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/headline.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/tappable.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';
import 'password_card.dart';
import 'rows.dart';
import 'scan_view.dart';
import '../widgets/sheet.dart';

/// How this device reaches the server: the address and key, the server's password, and what
/// the server says. The server reads Connected once Test connection passes here,
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
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, child) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // With nothing saved, it opens on the first run's welcome.
          if (settings.connection == null) const _Welcome(),
          child!,
          const PasswordCard(),
          _ServerStatus(onTest: _test),
        ],
      ),
      child: _KeyCard(tested: _tested),
    );
  }
}

/// The first run, over the sign-in form: what to do to connect.
class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final scan = AppScope.of(context).scanner != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Headline('Connect to your ', name: 'AnythingLLM', after: '.'),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              scan
                  ? 'Already set up on your computer? Scan its code and this phone is connected.'
                  : 'Sign in with the address and password of your AnythingLLM server.',
              style: Type.sans(13, color: t.muted, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// A test of the saved connection, once one is saved.
class _ServerStatus extends StatelessWidget {
  const _ServerStatus({required this.onTest});

  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        if (settings.connection == null) return const SizedBox.shrink();
        final testing = settings.check == ConnectionCheck.testing;
        // Test connection takes the line, as the design canvas draws it.
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: ActionRow(even: true, alignment: WrapAlignment.start, [
            AppButton(
              testing ? 'Testing…' : 'Test connection',
              onPressed: testing ? null : onTest,
            ),
          ]),
        );
      },
    );
  }
}

/// The address and key: saved, replaced or forgotten, or read from a QR code. A key is saved only once the server takes it.
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

  /// The shell, which holds whether the camera reads a code, so Back can stop it.
  late final ShellController _shell = AppScope.of(context).shell;

  /// Why the last scanned code could not be used.
  String? _scanProblem;
  Timer? _forgetTimer;

  /// The address the field shows as an example.
  static const _example = 'https://host.example.ts.net:3001';

  @override
  void initState() {
    super.initState();
    _url.text = _settings.connection?.baseUrl ?? '';
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
        _shell.setScanning(false);
        _scanProblem = error.message;
      });
      return;
    }
    setState(() {
      _shell.setScanning(false);
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
      listenable: Listenable.merge([_settings, _shell]),
      builder: (context, _) {
        final connection = _settings.connection;
        final set = connection != null;
        final editing = !set || _replacing;
        final saving = _settings.check == ConnectionCheck.testing;
        void startScan() => setState(() {
          _shell.setScanning(true);
          _scanProblem = null;
        });
        if (!set) return _firstRun(context, saving, startScan);
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
                          15,
                          weight: FontWeight.w500,
                          color: t.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AppBadge(
                  widget.tested && _settings.check == ConnectionCheck.ok
                      ? 'Connected'
                      : 'Saved',
                  kind: BadgeKind.ok,
                ),
              ],
            ),
            if (!_replacing)
              Text(
                connection.baseUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.mono(12.5, color: t.muted),
              ),
            Text(
              'The key is stored in this phone\'s keyring and never shown.',
              style: Type.sans(12.5, color: t.muted, height: 1.45),
            ),
            ActionRow(even: true, [
              AppButton(
                _replacing ? 'Cancel' : 'Edit connection',
                onPressed: () => setState(() {
                  _replacing = !_replacing;
                  _shell.setScanning(false);
                }),
              ),
              AppButton(
                _confirmForget ? 'Really forget it?' : 'Forget this server',
                onPressed: _forget,
              ),
            ]),
            if (_scanner case final scan? when editing && _shell.scanning)
              _scan(scan),
            if (editing && !_shell.scanning) ...[
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
                    onPressed: saving ? null : startScan,
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

  /// The camera view over the window, which keeps this card's scope.
  Widget _scan(CodeScanner scan) => OverlayWhile(
    open: _shell.scanning,
    overlay: (context) => ScanView(
      camera: scan(_scanned),
      onCancel: () => _shell.setScanning(false),
    ),
    child: const SizedBox.shrink(),
  );

  /// The first run: Scan QR code first where there is a camera, then the address and
  /// the password, each under its name, Sign in and Paste a key, or the key in the password's
  /// place.
  Widget _firstRun(BuildContext context, bool saving, VoidCallback startScan) {
    final t = Tokens.of(context);
    final scanner = _scanner;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (scanner != null) ...[
          _scan(scanner),
          AppButton(
            'Scan QR code',
            primary: true,
            onPressed: saving ? null : startScan,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 16),
            child: Center(
              child: SectionLabel(
                _pasteKey ? 'Or paste a key' : 'Or sign in',
                header: false,
              ),
            ),
          ),
        ],
        NamedControl(
          'Server address',
          quiet: true,
          labelled: true,
          AppField(
            controller: _url,
            label: 'Server address',
            hint: _example,
            keyboardType: TextInputType.url,
            autofillHints: const [AutofillHints.url],
          ),
        ),
        const SizedBox(height: 12),
        if (_pasteKey)
          NamedControl(
            'Developer API key',
            quiet: true,
            labelled: true,
            AppField(
              controller: _key,
              label: 'AnythingLLM developer API key',
              hint: 'Paste the AnythingLLM API key',
              obscure: true,
              keyboardType: TextInputType.visiblePassword,
            ),
          )
        else ...[
          NamedControl(
            'Password',
            quiet: true,
            labelled: true,
            AppField(
              controller: _password,
              label: 'Password',
              hint: 'Leave it empty if the server has none',
              obscure: true,
              keyboardType: TextInputType.visiblePassword,
              onSubmitted: (_) => saving ? null : _signIn(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The password AnythingLLM\'s web page asks for. The app makes its own developer key.',
            style: Type.sans(12.5, color: t.muted, height: 1.45),
          ),
        ],
        const SizedBox(height: 16),
        ActionRow(even: true, [
          AppButton(
            saving
                ? 'Checking…'
                : _pasteKey
                ? 'Save key'
                : 'Sign in',
            primary: scanner == null,
            onPressed: saving
                ? null
                : _pasteKey
                ? _save
                : _signIn,
          ),
        ]),
        Tappable(
          label: _pasteKey ? 'Use password' : 'Paste a key',
          onTap: () {
            if (!saving) setState(() => _pasteKey = !_pasteKey);
          },
          radius: BorderRadius.circular(Sizes.phoneControl),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            alignment: Alignment.center,
            child: Text(
              _pasteKey ? 'Use password' : 'Paste a key',
              style: Type.sans(16, weight: FontWeight.w500, color: t.accent),
            ),
          ),
        ),
        for (final note in [?_scanProblem, ?_settings.message]) ...[
          const SizedBox(height: 14),
          HelpText(note, status: true),
        ],
        if (_settings.keyringProblem case final problem?) ...[
          const SizedBox(height: 14),
          AlertBox(AlertKind.warn, problem.title, text: problem.text),
        ],
      ],
    );
  }
}
