import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/connection.dart';
import '../../core/ports.dart';
import '../app_scope.dart';
import '../state/settings_controller.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/headline.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';
import 'walkthrough.dart';
import 'rows.dart';
import 'scan_view.dart';
import '../widgets/sheet.dart';

/// How this device reaches the server: the address and developer key, and what the server
/// says. The server reads Connected once Test connection passes here,
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
      child: _KeyCard(tested: _tested, onTest: _test),
    );
  }
}

/// The first run, over the key form: what to do to connect.
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
                  : 'Enter your AnythingLLM server\'s address and a developer key.',
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
/// is kept, with the form to edit it under it while open, then Test connection, Edit connection
/// and Forget this server, one under another.
class _KeyCard extends StatefulWidget {
  const _KeyCard({required this.tested, required this.onTest});

  /// Whether Test connection was asked on this page, so a pass reads Connected.
  final bool tested;

  /// Tests the saved connection.
  final VoidCallback onTest;

  @override
  State<_KeyCard> createState() => _KeyCardState();
}

class _KeyCardState extends State<_KeyCard> {
  late final SettingsController _settings = AppScope.of(context).settings;
  late final CodeScanner? _scanner = AppScope.of(context).scanner;
  final _url = TextEditingController();
  final _key = TextEditingController();
  bool _replacing = false;
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
  }

  @override
  void dispose() {
    _forgetTimer?.cancel();
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async =>
      _saved(await _settings.connect(_url.text, _key.text));

  /// Closes the form once a connection was saved.
  void _saved(bool saved) {
    if (mounted && saved) {
      setState(() {
        _key.clear();
        _replacing = false;
      });
    }
  }

  /// Uses a scanned [code] as if its address and key had been typed, and connects with them,
  /// keeping where the code says its companions run.
  Future<void> _scanned(String code) async {
    final Pairing pairing;
    try {
      pairing = parsePairingCode(code);
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
      _url.text = pairing.connection.baseUrl;
      _key.text = pairing.connection.apiKey;
    });
    _saved(await _settings.pair(pairing));
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
        final saving = _settings.check == ConnectionCheck.testing;
        void startScan() => setState(() {
          _shell.setScanning(true);
          _scanProblem = null;
        });
        return _guide(
          startScan,
          set
              ? _connected(context, connection, saving, startScan)
              : _firstRun(context, saving, startScan),
        );
      },
    );
  }

  /// The saved connection's card, then, while Edit connection has it open, the fields; then
  /// Test connection, Edit connection and Forget this server.
  Widget _connected(
    BuildContext context,
    Connection connection,
    bool saving,
    VoidCallback startScan,
  ) {
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
        // Plain http to a private address: the key crosses that network unencrypted.
        if (connection.plainHttp)
          const AlertBox(
            AlertKind.warn,
            'Plain http',
            text:
                'This address is not encrypted, so the key travels as plain text on this '
                'network. Use it only on a network you trust.',
          ),
        if (_scanner case final scan? when _shell.scanning) _scan(scan),
        if (_replacing && !_shell.scanning)
          PanelCard(
            children: [
              AppField(
                controller: _url,
                label: 'AnythingLLM server address',
                hint: _example,
                keyboardType: TextInputType.url,
                autofillHints: const [AutofillHints.url],
              ),
              AppField(
                controller: _key,
                label: 'AnythingLLM developer API key',
                hint: 'Paste the AnythingLLM API key',
                obscure: true,
                // Not a password: AppField leaves it out of autofill, so no saved
                // login is offered for it.
                keyboardType: TextInputType.visiblePassword,
                onSubmitted: (_) => saving ? null : _save(),
              ),
              ActionRow([
                AppButton(
                  saving ? 'Checking…' : 'Save key',
                  primary: true,
                  onPressed: saving ? null : _save,
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
        AppButton(
          saving && !_replacing ? 'Testing…' : 'Test connection',
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
  }

  /// The camera view over the window, which keeps this card's scope, held by [child].
  Widget _scan(CodeScanner scan, {Widget child = const SizedBox.shrink()}) =>
      OverlayWhile(
        open: _shell.scanning,
        overlay: (context) => ScanView(
          camera: scan(_scanned),
          onCancel: () => _shell.setScanning(false),
          onHelp: () => _shell.showGuide(Guide.connect),
        ),
        child: child,
      );

  /// [child], with How connecting works over the whole window while the shell says so. Its
  /// end scans a code where there is a camera, through [startScan].
  Widget _guide(VoidCallback startScan, Widget child) {
    final canScan = _scanner != null;
    return OverlayWhile(
      open: _shell.guide == Guide.connect,
      overlay: (context) => Walkthrough(
        title: 'How connecting works',
        steps: connectSteps,
        onClose: () => _shell.showGuide(null),
        end: canScan ? 'Scan QR code' : 'Close',
        endAbout: canScan
            ? 'or close and type the address and key'
            : 'then type the address and key',
        onEnd: () {
          _shell.showGuide(null);
          if (canScan && !_shell.scanning) startScan();
        },
      ),
      child: child,
    );
  }

  /// The first run: Scan QR code first where there is a camera, then the address and the
  /// developer key, each under its name, where to make a key, Connect, and How connecting
  /// works.
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
            child: SectionLabel('Or enter a key', header: false),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'https, or http on your home network or Tailscale.',
            style: Type.note(t.muted),
          ),
        ),
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
            onSubmitted: (_) => saving ? null : _save(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Make one in AnythingLLM\'s web page: Settings, Developer API, Generate New API Key.',
            style: Type.note(t.muted),
          ),
        ),
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
          saving ? 'Checking…' : 'Connect',
          primary: scanner == null,
          onPressed: saving ? null : _save,
        ),
        if (_settings.keyringProblem case final problem?)
          AlertBox(AlertKind.warn, problem.title, text: problem.text),
        GuideLink(
          'How connecting works',
          onTap: () => _shell.showGuide(Guide.connect),
        ),
      ],
    );
  }
}
