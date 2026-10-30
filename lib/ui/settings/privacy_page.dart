import 'package:flutter/material.dart';

import '../../core/providers.dart';
import '../app_scope.dart';
import '../files/save_file.dart';
import '../state/notice.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import 'rows.dart';
import 'server_settings.dart';

/// Where a question and the passages found for it go, and Your chats, to export every chat on
/// the server as one file.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 20,
    children: [_WhereItGoes(), _YourChats()],
  );
}

/// The providers the server uses, and whether it sends its makers anonymous usage data.
class _WhereItGoes extends StatelessWidget {
  const _WhereItGoes();

  @override
  Widget build(BuildContext context) {
    final system = AppScope.of(context).system;
    return ServerSettings(
      builder: (values) {
        final telemetry = switch (values['DisableTelemetry']) {
          true || 'true' => false,
          _ => true,
        };
        return FieldCard([
          ReadOnlyRow(label: 'Chat model', value: chatModelPrivacy(values)),
          ReadOnlyRow(
            label: 'Document search model',
            value: searchModelPrivacy(values),
          ),
          ReadOnlyRow(label: 'Document storage', value: storagePrivacy(values)),
          FieldRow.toggle(
            label: 'Anonymous telemetry',
            help: 'The server sends anonymous usage data to AnythingLLM\'s makers.',
            value: telemetry,
            onChanged: system.saving
                ? null
                : (on) => system.saveSettings({
                    'DisableTelemetry': on ? 'false' : 'true',
                  }),
          ),
        ]);
      },
    );
  }
}

/// Your chats: Export chats saves every chat on the server, every user's on a server with
/// several users, as one CSV file where the person picks, through [saveFile]. Why it failed shows
/// under it.
class _YourChats extends StatefulWidget {
  const _YourChats();

  @override
  State<_YourChats> createState() => _YourChatsState();
}

class _YourChatsState extends State<_YourChats> {
  bool _exporting = false;
  Notice? _problem;

  /// The file's name: the server's chats on [day], as `anythingllm-chats-2026-10-30.csv`.
  static String _name(DateTime day) =>
      'anythingllm-chats-${day.toIso8601String().substring(0, 10)}.csv';

  Future<void> _export() async {
    final system = AppScope.of(context).system;
    setState(() {
      _exporting = true;
      _problem = null;
    });
    await saveFile(
      context,
      _name(DateTime.now()),
      system.exportChats,
      failTitle: 'Could not export the chats',
      report: (title, text) {
        if (mounted) setState(() => _problem = Notice(title, text));
      },
    );
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return PanelCard(
      spacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your chats', style: Type.body(t.ink)),
            Text(
              'Every chat on the server, as one spreadsheet file.',
              style: Type.note(t.ink),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            _exporting ? 'Exporting…' : 'Export chats',
            onPressed: _exporting ? null : _export,
          ),
        ),
        if (_problem case final problem?)
          AlertBox.notice(AlertKind.bad, problem),
      ],
    );
  }
}
