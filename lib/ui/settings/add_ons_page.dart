import 'package:flutter/material.dart';

import '../../core/apps.dart';
import '../../core/toolkit.dart';
import '../app_scope.dart';
import '../state/companion_watch.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';
import 'rows.dart';

/// What the Add-ons row says: which of them were found.
String addOnsSummary({required bool? apps, required bool? toolkit}) {
  final found = [
    if (apps == true) 'Apps server',
    if (toolkit == true) 'Toolkit',
  ];
  return found.isEmpty ? 'None found' : '${found.join(' and ')} found';
}

/// The servers that may run beside AnythingLLM, each with whether it was found, what it adds,
/// and where it runs: guessed beside AnythingLLM, or said by a pairing code or here, for one
/// reached through a tunnel or a proxy on an address of its own.
class AddOnsPage extends StatelessWidget {
  const AddOnsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 20,
      children: [
        _AddOn(
          companion: appsCompanion,
          title: 'Apps server',
          adds: 'Apps the agent makes, with their cards in answers.',
          watch: scope.apps,
        ),
        _AddOn(
          companion: toolkitCompanion,
          title: 'Toolkit',
          adds: 'Memory and Upcoming, and the agent\'s say over skills, memories and jobs.',
          watch: scope.toolkit,
        ),
        const PageNote(
          'Each runs on your server beside AnythingLLM. Found here once it answers at its '
          'address; Test connection on the Connection page asks again.',
        ),
      ],
    );
  }
}

/// One add-on: its name and whether it was found, what it adds, and its address to change.
class _AddOn extends StatefulWidget {
  const _AddOn({
    required this.companion,
    required this.title,
    required this.adds,
    required this.watch,
  });

  final Companion companion;
  final String title;
  final String adds;
  final CompanionWatch watch;

  @override
  State<_AddOn> createState() => _AddOnState();
}

class _AddOnState extends State<_AddOn> {
  final _address = TextEditingController();

  /// Why the last address typed could not be used.
  String? _problem;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = AppScope.of(context).settings;
    _address.text = '${settings.addressOf(widget.companion) ?? ''}';
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _save(String raw) async {
    final settings = AppScope.of(context).settings;
    final saved = await settings.setCompanion(widget.companion, raw);
    if (!mounted) return;
    setState(() {
      _problem = saved ? null : settings.message;
      if (saved) _address.text = '${settings.addressOf(widget.companion)}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final said = settings.companions.containsKey(widget.companion.service);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.watch, settings]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          FieldCard([
            InfoRow(
              widget.title,
              about: widget.adds,
              tag: AppBadge(
                switch (widget.watch.available) {
                  null => 'Checking',
                  true => 'Found',
                  false => 'Not found',
                },
                kind: widget.watch.available == true
                    ? BadgeKind.ok
                    : BadgeKind.warn,
              ),
            ),
          ]),
          PanelCard(
            children: [
              AppField(
                controller: _address,
                label: '${widget.title} address',
                hint: 'https://',
                keyboardType: TextInputType.url,
                autofillHints: const [AutofillHints.url],
                onSubmitted: _save,
              ),
              if (_problem case final problem?) HelpText(problem, status: true),
              ActionRow([
                if (said)
                  AppButton('Use the default', onPressed: () => _save('')),
                AppButton(
                  'Save address',
                  primary: true,
                  onPressed: () => _save(_address.text),
                ),
              ]),
            ],
          ),
        ],
      ),
    );
  }
}
