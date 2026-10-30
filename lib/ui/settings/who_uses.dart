import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/users.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/tappable.dart';
import 'rows.dart';

/// Who uses this app?, the sheet over the Connection page of a server with several users: what
/// the choice does, then the server's users, each over their role, the one picked in semibold
/// with a check, and Done. Done keeps the one picked as whom chats are saved as
/// ([PrefsController.chooseUser]) and reads the workspaces again for them; it is off until
/// someone is picked. Close leaves the choice as it was.
class WhoUsesSheet extends StatefulWidget {
  const WhoUsesSheet({super.key, required this.onDone});

  /// Closes the sheet.
  final VoidCallback onDone;

  @override
  State<WhoUsesSheet> createState() => _WhoUsesSheetState();
}

class _WhoUsesSheetState extends State<WhoUsesSheet> {
  late final _scope = AppScope.of(context);

  /// The id of the user picked here, the one chosen before until another is tapped.
  late int? _picked = _scope.prefs.chosenUser?.id;

  /// Saves chats as [user] from now on, and shows their workspaces when someone else was chosen.
  Future<void> _done(ServerUser user) async {
    final changed = _scope.prefs.chosenUser != user;
    widget.onDone();
    await _scope.prefs.chooseUser(user);
    if (changed) unawaited(_scope.chat.load());
  }

  @override
  Widget build(BuildContext context) {
    final system = _scope.system;
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: system,
      builder: (context, _) {
        final users = system.users;
        final picked = users.where((u) => u.id == _picked).firstOrNull;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'New chats are saved under this person, and the app shows only the '
                  'workspaces they can open. It is not a sign-in.',
                  style: Type.body(t.ink),
                ),
              ),
              if (users.isNotEmpty)
                Semantics(
                  container: true,
                  label: 'Chats saved as',
                  child: FieldCard([
                    for (final user in users)
                      _UserRow(
                        user,
                        picked: user.id == _picked,
                        onTap: () => setState(() => _picked = user.id),
                      ),
                  ]),
                )
              else if (system.usersProblem case final problem?)
                AlertBox.notice(AlertKind.bad, problem)
              else
                const HelpText('Reading who uses this server…', status: true),
              AppButton(
                'Done',
                primary: true,
                onPressed: picked == null ? null : () => _done(picked),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One of the server's users, a choice of the sheet's: their name over their role, and a check
/// in the accent at the end while [picked], when the name is semibold.
class _UserRow extends StatelessWidget {
  const _UserRow(this.user, {required this.picked, required this.onTap});

  final ServerUser user;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final role = user.roleLabel;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: picked,
      child: Tappable(
        label: [user.name, if (role.isNotEmpty) role].join(', '),
        selected: picked,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: Sizes.cardRow),
          padding: const EdgeInsets.symmetric(
            horizontal: FieldCard.inset,
            vertical: 10,
          ),
          child: Row(
            spacing: 14,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.name,
                      style: Type.body(
                        t.ink,
                        weight: picked ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (role.isNotEmpty) Text(role, style: Type.note(t.ink)),
                  ],
                ),
              ),
              if (picked) AppIcon('check', size: IconSize.row, color: t.accent),
            ],
          ),
        ),
      ),
    );
  }
}
