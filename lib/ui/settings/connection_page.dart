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
        ],
      ),
      child: _KeyCard(
        tested: _tested,
        onTest: _test,
        password: const PasswordCard(),
      ),
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Headline('Connect to your ', name: 'AnythingLLM', after: '.'),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              scan
                  ? 'Already set up on your computer? Scan its code and this phone is connected.'
                  : 'Sign in with the address and password of your AnythingLLM server.',
              style: Type.note(t.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// The address and key: saved, replaced or forgotten, or read from a QR code. A key is saved
/// only once the server takes it. Once one is saved, a card names the server and where its key
/// is kept, with the form to edit it under it while open, then [password], then Test connection,
/// Edit connection and Forget this server, one under another.
class _KeyCard extends StatefulWidget {
  const _KeyCard({
    required this.tested,
    required this.onTest,
    required this.password,
  });

  /// Whether Test connection was asked on this page, so a pass reads Connected.
  final bool tested;

  /// Tests the saved connection.
  final VoidCallback onTest;

  /// The server's password, under the key.
  final Widget password;

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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 20,
          children: [
            FieldCard([
              InfoRow(
                'AnythingLLM server',
                about: _replacing ? null : connection.baseUrl,
                mono: true,
                tag: AppBadge(
                  widget.tested && _settings.check == ConnectionCheck.ok
                      ? 'Connected'
                      : 'Saved',
                  kind: BadgeKind.ok,
                ),
              ),
              const InfoRow(
                'Developer key',
                about: 'Stored in this phone\'s keyring and never shown',
              ),
            ]),
            if (_scanner case final scan? when editing && _shell.scanning)
              _scan(scan),
            if (editing && !_shell.scanning)
              PanelCard(
                children: [
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
                      // Not a password: AppField leaves it out of autofill, so no saved
                      // login is offered for it.
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
              ),
            for (final note in [?_scanProblem, ?_settings.message])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: HelpText(note, status: true),
              ),
            if (_settings.keyringProblem case final problem?)
              AlertBox(AlertKind.warn, problem.title, text: problem.text),
            // The password's card, when it has something to show.
            if (connection.password != null ||
                _settings.auth == ServerAuth.password ||
                _settings.auth == ServerAuth.multiUser)
              widget.password,
            AppButton(
              saving && !editing ? 'Testing…' : 'Test connection',
              onPressed: saving ? null : widget.onTest,
            ),
            AppButton(
              _replacing ? 'Cancel' : 'Edit connection',
              onPressed: () => setState(() {
                _replacing = !_replacing;
                _shell.setScanning(false);
              }),
            ),
            AppButton(
              _confirmForget ? 'Really forget it?' : 'Forget this server',
              danger: true,
              onPressed: _forget,
            ),
          ],
        );
      },
    );
  }

  /// The camera view over the window, which keeps this card's scope, held by [child].
  Widget _scan(CodeScanner scan, {Widget child = const SizedBox.shrink()}) =>
      OverlayWhile(
        open: _shell.scanning,
        overlay: (context) => ScanView(
          camera: scan(_scanned),
          onCancel: () => _shell.setScanning(false),
        ),
        child: child,
      );

  /// The first run: Scan QR code first where there is a camera, then the address and
  /// the password, each under its name, Sign in and Paste a key, or the key in the password's
  /// place.
  Widget _firstRun(BuildContext context, bool saving, VoidCallback startScan) {
    final t = Tokens.of(context);
    final scanner = _scanner;
    final notes = [?_scanProblem, ?_settings.message];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        if (scanner != null) ...[
          _scan(
            scanner,
            child: AppButton(
              'Scan QR code',
              primary: true,
              onPressed: saving ? null : startScan,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SectionLabel(
              _pasteKey ? 'Or paste a key' : 'Or sign in',
              header: false,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'The password AnythingLLM\'s web page asks for. The app makes its own developer key.',
              style: Type.note(t.muted),
            ),
          ),
        ],
        // Why the last try failed, in a line kept for it.
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                for (final note in notes) HelpText(note, status: true),
              ],
            ),
          ),
        ),
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
        if (_settings.keyringProblem case final problem?)
          AlertBox(AlertKind.warn, problem.title, text: problem.text),
      ],
    );
  }
}
