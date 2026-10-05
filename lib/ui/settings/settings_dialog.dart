import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../state/settings_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';

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
                    NilsButton(
                      'Done',
                      primary: true,
                      onPressed: scope.shell.closeSettings,
                    ),
                  ],
                ),
                const _Section('AnythingLLM API'),
                const _KeyCard(),
                const _Section('Answers'),
                const _AnswersCard(),
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

/// The address and key: saved, replaced or forgotten. A key is saved only once the server takes
/// it.
class _KeyCard extends StatefulWidget {
  const _KeyCard();

  @override
  State<_KeyCard> createState() => _KeyCardState();
}

class _KeyCardState extends State<_KeyCard> {
  late final SettingsController _settings = AppScope.of(context).settings;
  final _url = TextEditingController();
  final _key = TextEditingController();
  bool _replacing = false;
  bool _confirmForget = false;
  Timer? _forgetTimer;

  @override
  void initState() {
    super.initState();
    _url.text = _settings.connection?.baseUrl ?? 'http://localhost:3001';
  }

  @override
  void dispose() {
    _forgetTimer?.cancel();
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _settings.connect(_url.text, _key.text);
    if (mounted && _settings.check == ConnectionCheck.ok) {
      setState(() {
        _key.clear();
        _replacing = false;
      });
    }
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
                        'AnythingLLM developer API key',
                        style: Type.sans(
                          14.5,
                          weight: FontWeight.w500,
                          color: t.ink,
                        ),
                      ),
                      Text(
                        set ? 'Saved in your system keyring. Never shown.' : 'Create one in AnythingLLM under Settings → Developer API, then paste it here.',
                        style: Type.sans(12.5, color: t.muted, height: 1.45),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                NilsBadge(
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
                  NilsButton(
                    _replacing ? 'Cancel' : 'Replace',
                    onPressed: () => setState(() {
                      _replacing = !_replacing;
                    }),
                  ),
                  NilsButton(
                    _confirmForget ? 'Delete it?' : 'Forget',
                    onPressed: _forget,
                  ),
                ],
              ),
            if (editing) ...[
              NilsField(
                controller: _url,
                label: 'AnythingLLM server address',
                hint: 'http://localhost:3001',
              ),
              NilsField(
                controller: _key,
                label: 'AnythingLLM developer API key',
                hint: 'Paste the AnythingLLM API key',
                obscure: true,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: NilsButton(
                  saving ? 'Checking…' : 'Save key',
                  primary: true,
                  onPressed: saving ? null : _save,
                ),
              ),
            ],
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

class _AnswersCard extends StatelessWidget {
  const _AnswersCard();

  @override
  Widget build(BuildContext context) {
    final prefs = AppScope.of(context).prefs;
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => _Card(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      'Only answer from my documents',
                      style: Type.sans(
                        14.5,
                        weight: FontWeight.w500,
                        color: t.ink,
                      ),
                    ),
                    Text(
                      'Otherwise Nilson may answer from general knowledge.',
                      style: Type.sans(12.5, color: t.muted),
                    ),
                  ],
                ),
              ),
              NilsSwitch(
                value: prefs.prefs.groundedOnly,
                label: 'Only answer from my documents',
                large: true,
                onChanged: prefs.setGroundedOnly,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
