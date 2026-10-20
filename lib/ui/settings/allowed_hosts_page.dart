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

/// The Allowed hosts page's question before a host is removed, in the shell's popup, so Back
/// closes it.
class AllowedHostSheet {
  const AllowedHostSheet(this.host);

  final String host;

  @override
  bool operator ==(Object other) =>
      other is AllowedHostSheet && other.host == host;

  @override
  int get hashCode => host.hashCode;
}

/// The hosts on the person's own network every skill may reach without asking, which Always
/// allow adds, read from the toolkit. A row asks before it removes its host.
class AllowedHostsPage extends StatelessWidget {
  const AllowedHostsPage({super.key});

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
          final AllowedHostSheet sheet => sheet,
          _ => null,
        };
        final hosts = toolkit.allowed;
        return PopupSheet(
          open: open != null,
          onClose: shell.closePopup,
          title: 'Allowed host',
          sheet: (context) => SheetQuestion(
            'Stop allowing ${open?.host}? A skill will ask again before it reaches it in a '
            'chat, and be refused out of one.',
            action: 'Remove',
            onKeep: shell.closePopup,
            onConfirm: open == null || toolkit.busy
                ? null
                : () {
                    shell.closePopup();
                    unawaited(toolkit.forgetHost(open.host));
                  },
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (toolkit.allowedProblem ?? toolkit.changeProblem
                  case final problem?) ...[
                AlertBox.notice(AlertKind.bad, problem),
                const SizedBox(height: 20),
              ],
              if (hosts == null) ...[
                if (toolkit.allowedLoading)
                  const HelpText('Loading…', status: true),
              ] else ...[
                FieldCard([
                  for (final host in hosts) _HostRow(host),
                  if (hosts.isEmpty)
                    const CardNote(
                      'None yet. When a skill asks in a chat, Always allow adds its host here.',
                    ),
                ]),
                const SizedBox(height: 20),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: FieldCard.inset),
                  child: PageNote(
                    'Hosts the server lets through itself, in FENCE_ALLOW, are allowed too '
                    'and not listed here.',
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

/// A host always allowed, with when, which a tap asks to remove.
class _HostRow extends StatelessWidget {
  const _HostRow(this.host);

  final AllowedHost host;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final added = switch (host.added) {
      final at? => 'Allowed ${whenText(at, clock.now())}',
      null => 'Allowed',
    };
    return NavRow(
      title: host.host,
      about: added,
      end: 'trash',
      heard: '${host.host}, $added. Remove',
      onTap: scope.toolkit.busy
          ? null
          : () => scope.shell.togglePopup(AllowedHostSheet(host.host)),
    );
  }
}
