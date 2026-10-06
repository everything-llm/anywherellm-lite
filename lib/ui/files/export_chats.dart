import 'package:flutter/material.dart';

import '../../core/server_models.dart';
import '../app_scope.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import 'save_file.dart';

/// Saves every chat on the server to a file, in the format chosen.
class ExportChats extends StatefulWidget {
  const ExportChats({super.key});

  @override
  State<ExportChats> createState() => _ExportChatsState();
}

class _ExportChatsState extends State<ExportChats> {
  String? _saved;

  /// Asks where to save first, so nothing is fetched when the person cancels.
  Future<void> _export(ChatExport format) async {
    final files = AppScope.of(context).files;
    final path = await saveFile(
      context,
      format.fileName,
      () => files.exportChats(format),
      failTitle: 'Could not save the chats',
    );
    if (path != null && mounted) setState(() => _saved = path);
  }

  @override
  Widget build(BuildContext context) {
    final files = AppScope.of(context).files;
    return ListenableBuilder(
      listenable: files,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HelpText(
            'Export every chat on the server, from every workspace, to a file in one of these formats.',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final format in ChatExport.values)
                AppButton(
                  format.label,
                  onPressed: files.exporting ? null : () => _export(format),
                ),
            ],
          ),
          if (files.exporting) ...[
            const SizedBox(height: 10),
            const HelpText('Exporting…', status: true),
          ] else if (_saved case final path?) ...[
            const SizedBox(height: 10),
            HelpText('Saved to $path', status: true),
          ],
        ],
      ),
    );
  }
}
