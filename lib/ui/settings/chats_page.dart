import 'package:flutter/material.dart';

import '../../core/chat_log.dart';
import '../../core/server_models.dart';
import '../app_scope.dart';
import '../files/save_file.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import 'rows.dart';

/// Every chat the server recorded, newest first, a page at a time, and every chat saved to a
/// file.
class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  String? _saved;

  @override
  void initState() {
    super.initState();
    // After the frame: the read tells its listeners at once, and some are built elsewhere.
    final system = AppScope.of(context).system;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) system.readChats();
    });
  }

  /// Fetches the chats in [format] and saves them where the person picks.
  Future<void> _export(ChatExport format) async {
    final system = AppScope.of(context).system;
    final path = await saveFile(
      context,
      format.fileName,
      () => system.exportChats(format),
      failTitle: 'Could not save the chats',
      report: system.reportExport,
    );
    if (path != null && mounted) setState(() => _saved = path);
  }

  @override
  Widget build(BuildContext context) {
    final system = AppScope.of(context).system;
    return ListenableBuilder(
      listenable: system,
      builder: (context, _) {
        final chats = system.chats;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            if (system.chatsProblem case final problem?)
              AlertBox(AlertKind.bad, problem.title, text: problem.text),
            if (chats == null)
              if (system.chatsProblem == null)
                const HelpText('Reading the chats…', status: true)
              else
                const SizedBox.shrink()
            else if (chats.isEmpty)
              const HelpText('No chats yet.', status: true)
            else
              LayoutBuilder(
                builder: (context, box) {
                  // As wide as a row needs to show its columns, inside the card's border and
                  // padding.
                  final wide = box.maxWidth - 34 >= FieldRow.sideBySide;
                  return FieldCard([
                    if (wide) const _Columns(),
                    for (final chat in chats) _ChatRow(chat, wide: wide),
                  ]);
                },
              ),
            if (system.chatsMore)
              ActionRow([
                AppButton(
                  system.readingChats ? 'Reading…' : 'Show more',
                  onPressed: system.readingChats ? null : system.moreChats,
                ),
              ]),
            const SubHead('Export'),
            if (system.exportProblem case final problem?)
              AlertBox(AlertKind.bad, problem.title, text: problem.text),
            PageActions([
              for (final format in ChatExport.values)
                AppButton(
                  format.label,
                  onPressed: system.exporting ? null : () => _export(format),
                ),
            ]),
            const PageNote(
              'Every chat on the server, from every workspace, in one file.',
            ),
            if (system.exporting)
              const HelpText('Exporting…', status: true)
            else if (_saved case final path?)
              HelpText('Saved to $path', status: true),
          ],
        );
      },
    );
  }
}

/// The names of the columns over the chats, where they show side by side.
class _Columns extends StatelessWidget {
  const _Columns();

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        spacing: 12,
        children: [
          SizedBox(width: 140, child: ColumnLabel('Workspace')),
          Expanded(child: ColumnLabel('Prompt')),
          SizedBox(width: 110, child: ColumnLabel('Sent', end: true)),
        ],
      ),
    ),
  );
}

/// One recorded chat: its workspace, question and when it was sent, in columns when [wide].
class _ChatRow extends StatelessWidget {
  const _ChatRow(this.chat, {required this.wide});

  final LoggedChat chat;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final workspace = chat.workspace.isEmpty
        ? 'Deleted workspace'
        : chat.workspace;
    final sent = switch (chat.at) {
      final at? => sentText(at.toLocal(), DateTime.now()),
      null => '',
    };
    final question = Text(
      chat.question,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Type.sans(13.5, color: t.ink, height: 1.45),
    );
    final muted = Type.sans(13.5, color: t.muted, height: 1.45);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: !wide
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                question,
                Text(
                  [workspace, sent].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ],
            )
          : Row(
              spacing: 12,
              children: [
                SizedBox(
                  width: 140,
                  child: Text(
                    workspace,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ),
                Expanded(child: question),
                SizedBox(
                  width: 110,
                  child: Text(sent, textAlign: TextAlign.end, style: muted),
                ),
              ],
            ),
    );
  }
}
