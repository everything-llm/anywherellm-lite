import 'package:flutter/material.dart';

import '../../core/ports.dart';
import '../app_scope.dart';
import '../state/settings_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';
import 'rows.dart';

/// The server's password, under the key, once the server has said it has one or a password is
/// saved. It signs in to the web UI's own routes, which the key does not open.
class PasswordCard extends StatefulWidget {
  const PasswordCard({super.key});

  @override
  State<PasswordCard> createState() => _PasswordCardState();
}

class _PasswordCardState extends State<PasswordCard> {
  late final SettingsController _settings = AppScope.of(context).settings;
  final _password = TextEditingController();
  bool _replacing = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await _settings.savePassword(_password.text);
    if (mounted && saved) {
      setState(() {
        _password.clear();
        _replacing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _settings,
    builder: (context, _) {
      final connection = _settings.connection;
      final auth = _settings.auth;
      final set = connection?.password != null;
      if (connection == null ||
          (!set &&
              auth != ServerAuth.password &&
              auth != ServerAuth.multiUser)) {
        return const SizedBox.shrink();
      }
      final t = Tokens.of(context);
      final checking = _settings.checkingPassword;
      final editing = !set || _replacing;
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: PanelCard(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Server password',
                        style: Type.sans(
                          14.5,
                          weight: FontWeight.w500,
                          color: t.ink,
                        ),
                      ),
                      Text(
                        auth == ServerAuth.multiUser && !set
                            ? 'This server has several users. Signing in with a user name is not supported, so its own commands, feedback, and Retry and Edit that replace the old exchange stay off.'
                            : set
                            ? 'Saved in your system keyring. Never shown.'
                            : 'Optional. This server has a password. With it, the app lists the server\'s own commands, marks answers good or bad, and Retry and Edit replace the old exchange.',
                        style: Type.sans(12.5, color: t.muted, height: 1.45),
                      ),
                    ],
                  ),
                ),
                if (auth != ServerAuth.multiUser || set) ...[
                  const SizedBox(width: 10),
                  AppBadge(
                    set ? 'Set' : 'Not set',
                    kind: set ? BadgeKind.ok : BadgeKind.accent,
                  ),
                ],
              ],
            ),
            if (set)
              ActionRow([
                AppButton(
                  _replacing ? 'Cancel' : 'Replace',
                  onPressed: () => setState(() => _replacing = !_replacing),
                ),
                AppButton('Forget', onPressed: _settings.forgetPassword),
              ]),
            if (editing && auth != ServerAuth.multiUser) ...[
              AppField(
                controller: _password,
                label: 'Server password',
                hint: 'The password AnythingLLM\'s web page asks for',
                obscure: true,
                keyboardType: TextInputType.visiblePassword,
                onSubmitted: (_) => checking ? null : _save(),
              ),
              ActionRow([
                AppButton(
                  checking ? 'Checking…' : 'Save password',
                  primary: true,
                  onPressed: checking ? null : _save,
                ),
              ]),
            ],
            if (_settings.passwordMessage case final message?)
              HelpText(message, status: true),
          ],
        ),
      );
    },
  );
}
