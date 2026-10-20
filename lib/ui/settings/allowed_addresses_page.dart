import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/asks.dart';
import '../../core/schedule.dart';
import '../app_scope.dart';
import '../widgets/basics.dart';
import '../widgets/fields.dart';
import '../widgets/sheet.dart';
import '../widgets/phone_page.dart';
import 'rows.dart';

/// The Allowed addresses page's question before an address is removed, in the shell's popup,
/// so Back closes it.
class AllowedOriginSheet {
  const AllowedOriginSheet(this.origin);

  final String origin;

  @override
  bool operator ==(Object other) =>
      other is AllowedOriginSheet && other.origin == origin;

  @override
  int get hashCode => origin.hashCode;
}

/// The addresses on the person's own network every skill may reach without asking, each one
/// origin (scheme, host and port), which Always allow adds, read from the toolkit. A row asks
/// before it removes its address. Opening it reads the list again when the last read failed.
class AllowedAddressesPage extends StatefulWidget {
  const AllowedAddressesPage({super.key});

  @override
  State<AllowedAddressesPage> createState() => _AllowedAddressesPageState();
}

class _AllowedAddressesPageState extends State<AllowedAddressesPage> {
  @override
  void initState() {
    super.initState();
    AppScope.of(context).toolkit.wantAllowed(retry: true);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final toolkit = scope.toolkit;
    return ListenableBuilder(
      listenable: Listenable.merge([toolkit, shell.popup]),
      builder: (context, _) {
        toolkit.wantAllowed();
        final open = switch (shell.popup.value) {
          final AllowedOriginSheet sheet => sheet,
          _ => null,
        };
        final origins = toolkit.allowed;
        return PopupSheet(
          open: open != null,
          onClose: shell.closePopup,
          title: 'Allowed address',
          sheet: (context) => SheetQuestion(
            'Stop allowing ${open?.origin}? A skill will ask again before it reaches it in '
            'a chat, and be refused out of one.',
            action: 'Remove',
            onKeep: shell.closePopup,
            onConfirm: open == null || toolkit.busy
                ? null
                : () {
                    shell.closePopup();
                    unawaited(toolkit.forgetOrigin(open.origin));
                  },
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Why a removal failed and why the list could not be read are both told.
              for (final problem in [
                ?toolkit.allowedProblem,
                ?toolkit.changeProblem,
              ]) ...[
                AlertBox.notice(AlertKind.bad, problem),
                const SizedBox(height: 20),
              ],
              if (origins == null) ...[
                if (toolkit.allowedLoading)
                  const HelpText('Loading…', status: true),
              ] else ...[
                FieldCard([
                  for (final origin in origins) _OriginRow(origin),
                  if (origins.isEmpty)
                    const CardNote(
                      'None yet. When a skill asks in a chat, Always allow adds its address here.',
                    ),
                ]),
                const SizedBox(height: 20),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: FieldCard.inset),
                  child: PageNote(
                    'Hosts the server lets through itself, in FENCE_ALLOW, are allowed on '
                    'every port and not listed here.',
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// An address always allowed, with when, which a tap asks to remove.
class _OriginRow extends StatelessWidget {
  const _OriginRow(this.origin);

  final AllowedOrigin origin;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final added = switch (origin.added) {
      final at? => 'Allowed ${whenText(at, clock.now())}',
      null => 'Allowed',
    };
    return NavRow(
      title: origin.origin,
      about: added,
      mono: true,
      end: 'trash',
      heard: '${origin.origin}, $added. Remove',
      onTap: scope.toolkit.busy
          ? null
          : () => scope.shell.togglePopup(AllowedOriginSheet(origin.origin)),
    );
  }
}
