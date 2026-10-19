import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
import '../widgets/keyboard_up.dart';
import '../widgets/scroll_fades.dart';
import '../widgets/window_insets.dart';
import 'walkthrough.dart';
import 'rows.dart';
import 'scan_view.dart';
import '../widgets/sheet.dart';

/// How this device reaches the server: the address and developer key, and what the server
/// says. The server reads Connected once Test connection passes here,
/// until the page closes or the connection changes or fails a test.
class ConnectionPage extends StatelessWidget {
  const ConnectionPage({super.key});

  @override
  Widget build(BuildContext context) => const _KeyCard();
}

/// The first run, over the key form: what to do to connect, inset to line up with the field labels.
class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final scan = AppScope.of(context).scanner != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          const Headline('Connect to your ', name: 'AnythingLLM', after: '.'),
          Text(
            scan
                ? 'Already set up on your computer? Scan its code and this phone is connected.'
                : 'Enter your AnythingLLM server\'s address and a developer key.',
            style: Type.lead(t.muted),
          ),
        ],
      ),
    );
  }
}

/// A line across the page with [label] centred in it, where one way in gives way to another.
class _OrDivider extends StatelessWidget {
  const _OrDivider(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final line = Expanded(
      child: Divider(height: 1, thickness: 1, color: t.line),
    );
    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            spacing: 12,
            children: [
              line,
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Type.sans(13, color: t.muted),
                ),
              ),
              line,
            ],
          ),
        ),
      ),
    );
  }
}

/// The address and key: saved, replaced or forgotten, or read from a QR code. A key is saved
/// only once the server takes it. Once one is saved, a card names the server and where its key
/// is kept, with the form to edit it under it while open, then Test connection, Edit connection
/// and Forget this server, one under another.
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
  bool _replacing = false;
  bool _confirmForget = false;

  /// Whether Test connection was asked on this page, so a pass reads Connected.
  bool _tested = false;

  /// The shell, which holds whether the camera reads a code, so Back can stop it.
  late final ShellController _shell = AppScope.of(context).shell;

  /// Why the last scanned code could not be used.
  String? _scanProblem;

  /// The first run's scroll, kept at its end while the keyboard rises, so the fields show
  /// above Connect, until the person scrolls it.
  final _scroll = ScrollController();
  bool _wasTyping = false;
  bool _pinned = false;
  Timer? _forgetTimer;

  /// The address the field shows as an example.
  static const _example = 'https://host.example.ts.net:3001';

  @override
  void initState() {
    super.initState();
    _url.text = _settings.connection?.baseUrl ?? '';
    _shell.addListener(_takePairing);
    WidgetsBinding.instance.addPostFrameCallback((_) => _takePairing());
  }

  /// Connects with a pairing code [ShellController.pairWith] left, as with a scanned one.
  void _takePairing() {
    if (!mounted) return;
    if (_shell.takePairing() case final code?) unawaited(_scanned(code));
  }

  @override
  void dispose() {
    _shell.removeListener(_takePairing);
    _forgetTimer?.cancel();
    _scroll.dispose();
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async =>
      _saved(await _settings.connect(_url.text, _key.text));

  /// Tests the saved connection.
  void _test() {
    setState(() => _tested = true);
    unawaited(_settings.testSaved());
  }

  /// The address field, named [label] to a screen reader.
  Widget _urlField(String label) => AppField(
    controller: _url,
    label: label,
    hint: _example,
    keyboardType: TextInputType.url,
    autofillHints: const [AutofillHints.url],
  );

  /// The developer key field, which sends the form on Enter unless it is [saving].
  Widget _keyField(bool saving) => SecretField(
    controller: _key,
    label: 'AnythingLLM developer API key',
    hint: 'Paste the AnythingLLM API key',
    // Not a password: AppField leaves it out of autofill, so no saved login is offered for it.
    keyboardType: TextInputType.visiblePassword,
    onSubmitted: (_) => saving ? null : _save(),
  );

  /// Why the last scan or try failed, when it did.
  List<String> get _notes => [?_scanProblem, ?_settings.message];

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
  /// keeping where the code says its companions run. Over a saved server the form opens, so a
  /// key the server refuses shows there.
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
      if (_settings.connection != null) _replacing = true;
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
              _tested && _settings.check == ConnectionCheck.ok
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
              _urlField('AnythingLLM server address'),
              _keyField(saving),
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
        for (final note in _notes)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: HelpText(note, status: true),
          ),
        if (_settings.keyringProblem case final problem?)
          AlertBox.notice(AlertKind.warn, problem),
        AppButton(
          saving && !_replacing ? 'Testing…' : 'Test connection',
          primary: true,
          onPressed: saving ? null : _test,
        ),
        AppButton(
          _replacing ? 'Cancel' : 'Edit connection',
          onPressed: () => setState(() {
            _replacing = !_replacing;
            _shell.setScanning(false);
            // Cancel lets go of what was typed or scanned, so the form opens on the saved
            // connection next time.
            if (!_replacing) {
              _url.text = connection.baseUrl;
              _key.clear();
            }
          }),
        ),
        const SizedBox(height: 8),
        AppButton(
          _confirmForget ? 'Really forget it?' : 'Forget this server',
          danger: true,
          quiet: true,
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
        initial: _shell.guideStep,
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

  /// [child], the first run's scroll, held at its end while the keyboard is [typing] up, which
  /// is where the fields are, until a drag moves it. It stops short of the end where the end would
  /// take the field in use out of view, under the top fade.
  Widget _atEnd(bool typing, {required Widget child}) {
    if (typing && !_wasTyping) _pinned = true;
    if (!typing) _pinned = false;
    _wasTyping = typing;
    if (_pinned) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pinned && _scroll.hasClients) {
          final position = _scroll.position;
          final end = position.maxScrollExtent;
          _scroll.jumpTo(
            (_focusTop() ?? end).clamp(position.minScrollExtent, end),
          );
        }
      });
    }
    return NotificationListener<ScrollStartNotification>(
      onNotification: (n) {
        if (n.dragDetails != null) _pinned = false;
        return false;
      },
      child: child,
    );
  }

  /// The scroll offset that puts the top of the field in use just under the first run's top
  /// fade, or null when no field in this scroll has the focus.
  double? _focusTop() {
    final focus = FocusManager.instance.primaryFocus?.context;
    final scrollable = focus?.findAncestorStateOfType<ScrollableState>();
    final box = focus?.findRenderObject();
    if (scrollable?.position != _scroll.position || box == null) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(box, 0).offset - ScrollFades.height;
  }

  /// The first run: the welcome, Scan QR code first where there is a camera, then the address and
  /// the developer key, each under its name, where to find a key, and Connect, in groups 28
  /// apart with 12 or less inside one. Connect is the filled button; Scan QR code is outlined,
  /// with a QR icon before its label. It is top-aligned and scrolls, so a short screen loses
  /// nothing: How connecting works sits at the foot while there is room and follows Connect where
  /// there is not. With the keyboard up Connect leaves the page and stays above the keyboard, in
  /// a bar of its own.
  Widget _firstRun(BuildContext context, bool saving, VoidCallback startScan) {
    final scanner = _scanner;
    final typing = KeyboardUp.of(context);
    final t = Tokens.of(context);
    final connect = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        // Why the last try failed, which takes room only while there is something to say.
        if (_notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                for (final note in _notes) HelpText(note, status: true),
              ],
            ),
          ),
        AppButton(
          saving ? 'Checking…' : 'Connect',
          primary: true,
          onPressed: saving ? null : _save,
        ),
        if (_settings.keyringProblem case final problem?)
          AlertBox.notice(AlertKind.warn, problem),
      ],
    );
    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 28,
      children: [
        const _Welcome(),
        if (scanner != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 20,
            children: [
              _scan(
                scanner,
                child: AppButton(
                  'Scan QR code',
                  leading: 'qr',
                  onPressed: saving ? null : startScan,
                ),
              ),
              const _OrDivider('or enter a key'),
            ],
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            NamedControl(
              'Server address',
              quiet: true,
              labelled: true,
              _urlField('Server address'),
            ),
            NamedControl(
              'Developer API key',
              quiet: true,
              labelled: true,
              _keyField(saving),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextAction.plain(
                'Where do I find a key?',
                () => _shell.showGuide(Guide.connect, step: connectKeyStep),
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (!typing) connect,
      ],
    );
    const top = 56.0;
    final foot = 8.0 + WindowInsets.of(context).bottom;
    final bottom = typing ? 16.0 : foot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => _atEnd(
              typing,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(16, top, 16, bottom),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(0, box.maxHeight - top - bottom),
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.topLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 680),
                            child: page,
                          ),
                        ),
                        const Spacer(),
                        if (!typing)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: GuideLink(
                              'How connecting works',
                              onTap: () => _shell.showGuide(Guide.connect),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (typing)
          DecoratedBox(
            decoration: BoxDecoration(
              color: t.bg,
              border: Border(top: BorderSide(color: t.line2)),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: connect,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
