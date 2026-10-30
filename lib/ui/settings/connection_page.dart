import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/connection.dart';
import '../../core/ports.dart';
import '../app_scope.dart';
import '../share/shared_item.dart';
import '../shell_popup.dart';
import '../state/prefs_controller.dart';
import '../state/settings_controller.dart';
import '../state/shell_controller.dart';
import '../state/system_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/headline.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';
import '../widgets/keyboard_up.dart';
import '../widgets/phone_page.dart';
import '../widgets/scroll_fades.dart';
import '../widgets/window_insets.dart';
import 'walkthrough.dart';
import 'rows.dart';
import 'scan_view.dart';
import 'who_uses.dart';
import '../widgets/sheet.dart';

/// How this device reaches the server: the address and developer key, and what the server
/// says. The server reads Connected once Test connection passes here,
/// until the page closes or the connection changes or fails a test. On a server with several
/// users it says whom chats are saved as, which opens Who uses this app?, and that the key
/// opens every user's chats.
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
                ? 'Already set up on your computer? Scan its code, or paste its pairing link as '
                      'the address.'
                : 'Enter your AnythingLLM server\'s address and a developer key, or paste a '
                      'pairing link as the address.',
            style: Type.body(t.muted),
          ),
        ],
      ),
    );
  }
}

/// [button] 52 tall, as the saved connection's own buttons are, one under another across the
/// page.
class _Tall extends StatelessWidget {
  const _Tall(this.button);

  final Widget button;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 52),
    child: button,
  );
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
                  style: Type.note(t.ink),
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
/// is kept, and on a server with several users whom chats are saved as, with the form to edit it
/// under it while open, then Test connection, Edit connection and Forget this server, one under
/// another. Who uses this app? opens by itself once after connecting to a server with several
/// users while no one is chosen there.
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

  /// Whether Test connection was asked on this page, so a pass reads Connected.
  bool _tested = false;

  /// The shell, which holds whether the camera reads a code, so Back can stop it.
  late final ShellController _shell = AppScope.of(context).shell;

  /// Whether the server has several users, and who they are.
  late final SystemController _system = AppScope.of(context).system;

  /// Whom chats are saved as.
  late final PrefsController _prefs = AppScope.of(context).prefs;

  /// Why the last scanned code could not be used.
  String? _scanProblem;

  /// The first run's scroll, kept at its end while the keyboard rises, so the fields show
  /// above Connect, until the person scrolls it.
  final _scroll = ScrollController();
  bool _wasTyping = false;
  bool _pinned = false;

  /// The address the field shows as an example.
  static const _example = 'https://host.example.ts.net:3001';

  @override
  void initState() {
    super.initState();
    _url.text = _settings.connection?.baseUrl ?? '';
    _shell.addListener(_takePairing);
    _system.addListener(_takeWhoUses);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _takePairing();
      _takeWhoUses();
    });
    if (_settings.configured) _system.wantUsers();
  }

  /// Opens Who uses this app? when [SystemController.askWhoUses] asked for it after connecting
  /// and the server has several users, unless someone is chosen there already.
  void _takeWhoUses() {
    if (!mounted || !_system.takeWhoUses() || _prefs.chosenUser != null) return;
    if (_shell.popup.value != Popup.whoUses) _shell.togglePopup(Popup.whoUses);
  }

  /// Connects with the pairing code [ShellController.pairWith] left once Connect to this server?
  /// was answered, for a code scanned here or a link another app opened.
  void _takePairing() {
    if (!mounted) return;
    if (_shell.takePairing() case final code?) unawaited(_pair(code));
  }

  @override
  void dispose() {
    _shell.removeListener(_takePairing);
    _system.removeListener(_takeWhoUses);
    _scroll.dispose();
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  /// Saves the typed address and key once they open the server, and closes the form. A pairing
  /// link pasted as the address is offered as a scanned code is, and the key field is not read.
  Future<void> _save() async {
    if (sharedTextItem(_url.text) case SharedPairing(:final code)) {
      setState(() => _scanProblem = null);
      _offer(code);
      return;
    }
    if (await _settings.connect(_url.text, _key.text)) {
      _system.askWhoUses();
      if (mounted) setState(_backToSaved);
    }
  }

  /// Tests the saved connection.
  void _test() {
    setState(() => _tested = true);
    unawaited(_settings.testSaved());
  }

  /// The address field, named [label] to a screen reader, edged as [invalid] when what the
  /// last try said is about it.
  Widget _urlField(String label, {bool invalid = false}) => AppField(
    controller: _url,
    label: label,
    hint: _example,
    keyboardType: TextInputType.url,
    autofillHints: const [AutofillHints.url],
    invalid: invalid,
  );

  /// The developer key field, which sends the form on Enter unless it is [saving].
  Widget _keyField(bool saving, {bool invalid = false}) => SecretField(
    controller: _key,
    label: 'AnythingLLM developer API key',
    hint: 'Paste the AnythingLLM API key',
    // Not a password: AppField leaves it out of autofill, so no saved login is offered for it.
    keyboardType: TextInputType.visiblePassword,
    onSubmitted: (_) => saving ? null : _save(),
    invalid: invalid,
  );

  /// Why the last scan or try failed, when it did, or what the last save said; with [fields],
  /// only what is about neither field, since each field says its own under it.
  List<String> _notes({bool fields = false}) => [
    ?_scanProblem,
    if (!fields || _settings.wrong == null) ?_settings.message,
  ];

  /// What the last try said is wrong with [field], or null.
  String? _wrongWith(ConnectionField field) =>
      _settings.wrong == field ? _settings.message : null;

  /// Closes the form on the saved connection, letting go of what was typed.
  void _backToSaved() {
    _replacing = false;
    _url.text = _settings.connection?.baseUrl ?? '';
    _key.clear();
  }

  /// Offers a scanned or pasted [code] in Connect to this server?, as a tapped link is, which
  /// says why when it is not a pairing code: a code on a sticker can name any server, so none
  /// replaces the saved one unasked.
  void _offer(String code) {
    _shell
      ..setScanning(false)
      ..showShared(SharedPairing(code));
  }

  /// Connects with the address and key [code] holds, and says why when it cannot. Nothing of the code is put in the form, which goes back to the
  /// saved connection whether it paired or not: a key typed after a failed code would go to the
  /// address it named.
  Future<void> _pair(String code) async {
    final Connection pairing;
    try {
      pairing = parsePairingCode(code);
    } on ApiException catch (error) {
      setState(() => _scanProblem = error.message);
      return;
    }
    setState(() => _scanProblem = null);
    if (await _settings.pair(pairing)) _system.askWhoUses();
    if (mounted) setState(_backToSaved);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_settings, _shell, _system, _prefs]),
      builder: (context, _) {
        final connection = _settings.connection;
        final set = connection != null;
        final saving = _settings.check == ConnectionCheck.testing;
        void startScan() => setState(() {
          _shell.setScanning(true);
          _scanProblem = null;
        });
        return _guide(
          set
              ? _connected(context, connection, saving, startScan)
              : _firstRun(context, saving, startScan),
        );
      },
    );
  }

  /// The saved connection's card, with whom chats are saved as on a server with several users,
  /// then the warning that the key opens every user's chats; then, while Edit connection has it
  /// open, the fields; then Test connection, Edit connection and Forget this server, which asks
  /// first.
  Widget _connected(
    BuildContext context,
    Connection connection,
    bool saving,
    VoidCallback startScan,
  ) {
    final several = _system.multiUser == true;
    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 20,
      children: [
        FieldCard([
          InfoRow(
            'AnythingLLM server',
            about: _replacing ? null : connection.baseUrl,
            mono: true,
            // Saved says nothing of whether it answers, so only Connected is a success.
            tag: _tested && _settings.check == ConnectionCheck.ok
                ? const AppBadge('Connected', kind: BadgeKind.ok)
                : const AppBadge('Saved', kind: BadgeKind.plain),
          ),
          const InfoRow(
            'Developer key',
            about: 'Stored in this phone\'s keyring and never shown',
          ),
          if (several) _savedAs(),
        ]),
        if (several)
          const AlertBox(
            AlertKind.warn,
            'This server has several users',
            text:
                'The key opens all of it: anyone with this phone or the key can read every '
                'chat, whoever it is saved as.',
          ),
        // Plain http to a private address: the key crosses unencrypted whatever network the
        // phone is on, where that name or address may be another machine's.
        if (connection.plainHttp)
          AlertBox(
            AlertKind.warn,
            'Plain http',
            text: plainHttpWarning(connection.host),
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
        for (final note in _notes())
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: HelpText(note, status: true),
          ),
        if (_settings.keyringProblem case final problem?)
          AlertBox.notice(AlertKind.warn, problem),
        _Tall(
          AppButton(
            saving && !_replacing ? 'Testing…' : 'Test connection',
            primary: true,
            onPressed: saving ? null : _test,
          ),
        ),
        _Tall(
          AppButton(
            _replacing ? 'Cancel' : 'Edit connection',
            onPressed: () => setState(() {
              _replacing = !_replacing;
              _shell.setScanning(false);
              if (!_replacing) _backToSaved();
            }),
          ),
        ),
        _Tall(
          AppButton(
            'Forget this server',
            danger: true,
            quiet: true,
            onPressed: () => _shell.togglePopup(Popup.forgetServer),
          ),
        ),
      ],
    );
    final asked = ShellPopup(
      popup: Popup.whoUses,
      title: 'Who uses this app?',
      present: several,
      builder: (context, close) => WhoUsesSheet(onDone: close),
      child: card,
    );
    return ShellPopup(
      popup: Popup.forgetServer,
      title: 'Forget this server',
      builder: (context, close) => SheetQuestion(
        'Forget ${connection.host}? Its key leaves this phone, and connecting again takes the '
        'key or a pairing code.',
        action: 'Forget',
        onKeep: close,
        onConfirm: () {
          close();
          unawaited(_settings.clear());
        },
      ),
      child: asked,
    );
  }

  /// Chats saved as, and whom, on a server with several users, which opens Who uses this app?
  /// to choose another.
  Widget _savedAs() {
    final who = _prefs.chosenUser?.name ?? 'No one chosen yet';
    return NavRow(
      title: 'Chats saved as',
      about: who,
      heard: 'Chats saved as $who. Change',
      onTap: () => _shell.togglePopup(Popup.whoUses),
    );
  }

  /// The camera view over the window, which keeps this card's scope, held by [child].
  Widget _scan(CodeScanner scan, {Widget child = const SizedBox.shrink()}) =>
      OverlayWhile(
        open: _shell.scanning,
        overlay: (context) => ScanView(
          camera: scan(_offer),
          onCancel: () => _shell.setScanning(false),
          onHelp: () => _shell.showGuide(Guide.connect),
        ),
        child: child,
      );

  /// [child], with How connecting works over the whole window while the shell says so. Its
  /// end, Enter the address and key, closes it on this page's fields, and the camera with it.
  Widget _guide(Widget child) => OverlayWhile(
    open: _shell.guide == Guide.connect,
    overlay: (context) => Walkthrough(
      title: 'How connecting works',
      steps: connectSteps,
      initial: _shell.guideStep,
      onClose: () => _shell.showGuide(null),
      end: 'Enter the address and key',
      endAbout: 'Closes this guide',
      onEnd: () {
        _shell
          ..showGuide(null)
          ..setScanning(false);
      },
    ),
    child: child,
  );

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
  /// the developer key, each under its name and over the room kept for what is wrong with it, so
  /// an error never moves the page, where to find a key, and Connect, in groups 28 apart with 12
  /// or less inside one. Connect is the filled button; Scan QR code is outlined,
  /// with a QR icon before its label. It is top-aligned and scrolls, so a short screen loses
  /// nothing: How connecting works sits at the foot while there is room and follows Connect where
  /// there is not. With the keyboard up Connect leaves the page and stays above the keyboard, in
  /// a bar of its own.
  Widget _firstRun(BuildContext context, bool saving, VoidCallback startScan) {
    final scanner = _scanner;
    final typing = KeyboardUp.of(context);
    final t = Tokens.of(context);
    final notes = _notes(fields: true);
    final addressWrong = _wrongWith(ConnectionField.address);
    final keyWrong = _wrongWith(ConnectionField.key);
    final connect = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        // Why a scan or a pairing failed, which takes room only while there is something to say.
        if (notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                for (final note in notes) HelpText(note, status: true),
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
        // Each field's message room spaces it from the next.
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            NamedControl(
              'Server address',
              quiet: true,
              labelled: true,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 6,
                children: [
                  _urlField('Server address', invalid: addressWrong != null),
                  FieldMessage(error: addressWrong),
                ],
              ),
            ),
            NamedControl(
              'Developer API key',
              quiet: true,
              labelled: true,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 6,
                children: [
                  _keyField(saving, invalid: keyWrong != null),
                  FieldMessage(error: keyWrong),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextAction.plain(
                'Where do I find a key?',
                () => _shell.showGuide(Guide.connect, step: connectKeyStep),
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
              color: t.ground,
              border: Border(top: BorderSide(color: t.line)),
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
