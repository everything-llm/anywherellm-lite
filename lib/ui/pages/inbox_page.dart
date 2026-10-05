import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../app_scope.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/drop_zone.dart';
import '../widgets/rows.dart';
import 'page_frame.dart';

/// The markdown files staged for adding, and the way to stage more. Filing one into a library
/// is done by a chat client with the nils tools, such as AnythingLLM, not here.
class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  @override
  void initState() {
    super.initState();
    AppScope.of(context).inbox.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final inbox = AppScope.of(context).inbox;
    return ListenableBuilder(
      listenable: inbox,
      builder: (context, _) => PageFrame(
        children: [
          const PageHead(
            'Inbox',
            sub:
                'Markdown files staged here are filed into a library by a chat client with the nils '
                'tools, such as AnythingLLM. Nothing here reads or files them.',
          ),
          DropZone(onFiles: inbox.upload, onProblem: inbox.report),
          for (final problem in inbox.problems)
            AlertBox(AlertKind.bad, problem.title, text: problem.text),
          if (inbox.staged.isEmpty)
            const EmptyState(
              'Nothing staged yet',
              'Files you stage appear here.',
            )
          else
            ListSection('Staged', [
              for (final name in inbox.staged)
                NilsRow(title: name, leading: _Extension(name)),
            ]),
        ],
      ),
    );
  }
}

/// The file type, on a tile where a row's icon would go.
class _Extension extends StatelessWidget {
  const _Extension(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      width: 32,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.accentbg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        sourceExt(name),
        style: Type.sans(
          9.5,
          weight: FontWeight.w600,
          color: t.accent,
          letterSpacing: 0.29,
        ),
      ),
    );
  }
}
