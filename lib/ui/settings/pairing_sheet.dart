import 'package:flutter/widgets.dart';

import '../../core/connection.dart';
import '../../core/errors.dart';
import '../../core/toolkit.dart';
import '../app_scope.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/sheet.dart';
import 'rows.dart';

/// Connect to this server?, for a pairing link another app opened or shared: the server it
/// names, the toolkit's address when it brings one, a warning for each over plain http, and
/// which saved server it replaces, then Cancel and Connect. A link can come from any page or
/// message, so it never connects without asking. Connect hands it to the Connection page, which
/// pairs as with a scanned code and shows how it went. A link that cannot be read says why.
class PairingSheet extends StatelessWidget {
  const PairingSheet(this.code, {super.key});

  final String code;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final Pairing pairing;
    try {
      pairing = parsePairingCode(code);
    } on ApiException catch (error) {
      return SheetFrame(
        title: 'Pairing link',
        onClose: shell.closeShared,
        child: HelpText(error.message, status: true),
      );
    }
    final saved = scope.settings.connection;
    final toolkit = pairing.companions[toolkitCompanion.code];
    // Every address the key would go to over plain http.
    final plain = {
      if (pairing.connection.plainHttp) pairing.connection.host,
      if (toolkit != null && toolkit.scheme == 'http') toolkit.host,
    };
    return SheetFrame(
      title: 'Connect to this server?',
      onClose: shell.closeShared,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            FieldCard([
              InfoRow(
                'AnythingLLM server',
                about: pairing.connection.baseUrl,
                mono: true,
              ),
              if (toolkit != null)
                InfoRow(toolkitCompanion.name, about: '$toolkit', mono: true),
            ]),
            for (final host in plain)
              AlertBox(
                AlertKind.warn,
                'Plain http',
                text: plainHttpWarning(host),
              ),
            HelpText(
              [
                if (saved != null) 'It replaces ${saved.host}.',
                'Connect only to a server you set up.',
              ].join(' '),
            ),
            ActionRow(even: true, [
              AppButton('Cancel', onPressed: shell.closeShared),
              AppButton(
                'Connect',
                primary: true,
                onPressed: () => shell
                  ..closeShared()
                  ..pairWith(code),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
