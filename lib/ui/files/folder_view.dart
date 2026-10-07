import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/files.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/confirm_box.dart';
import '../widgets/upload_queue.dart';
import 'export_chats.dart';
import 'vector_count.dart';
import '../widgets/fields.dart';
import '../widgets/inline_input.dart';
import '../widgets/tappable.dart';

/// A folder of the tree: what it holds, its contents, and what can be added to it.
class FolderView extends StatelessWidget {
  const FolderView(this.node, {super.key});

  final FileNode node;

  static String _about(NodeKind kind) => switch (kind) {
    NodeKind.workspaces => 'Every workspace on the server.',
    NodeKind.workspace =>
      'Its system prompt, answer settings, documents and chats.',
    NodeKind.docs => 'The documents this workspace answers from. Each links to the library: detaching one leaves it there.',
    NodeKind.chats => 'Each chat as Markdown. The server keeps chats as a log, so they cannot be edited.',
    NodeKind.library => 'The shared pool of documents. A document lives here once, and workspaces link to it.',
    NodeKind.libraryFolder =>
      'Deleting a document here takes it out of every workspace that uses it.',
    NodeKind.systemFolder => 'The server\'s settings, with every secret left out, its vector count, and every chat to export.',
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final files = scope.files;
    final t = Tokens.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(_about(node.kind), style: Type.sans(14, color: t.muted)),
        const SizedBox(height: 16),
        if (node.kind == NodeKind.systemFolder) ...[
          const VectorCount(),
          const SizedBox(height: 16),
          const ExportChats(),
          const SizedBox(height: 16),
        ],
        if (node.kind == NodeKind.library) ...[
          const _NewFolder(),
          const SizedBox(height: 16),
        ],
        if (node.kind == NodeKind.libraryFolder) ...[
          _DeleteFolder(node),
          const SizedBox(height: 16),
          UploadQueue(
            onSend: (picked) => files.upload(node.ref!, picked),
            onProblem: files.report,
          ),
          if (files.sending case final name?) ...[
            const SizedBox(height: 10),
            HelpText('Adding $name…', status: true),
          ],
          const SizedBox(height: 16),
        ],
        if (node.children.isEmpty)
          Text(
            files.loading ? 'Loading…' : 'Empty.',
            style: Type.sans(13.5, color: t.muted),
          ),
        for (final child in node.children) _ChildRow(child),
        if (node.kind == NodeKind.docs) ...[
          const SizedBox(height: 24),
          _Attach(node.slug!),
        ],
      ],
    );
  }
}

/// Deletes a library folder with its documents, after asking once more.
class _DeleteFolder extends StatefulWidget {
  const _DeleteFolder(this.node);

  final FileNode node;

  @override
  State<_DeleteFolder> createState() => _DeleteFolderState();
}

class _DeleteFolderState extends State<_DeleteFolder> {
  bool _confirming = false;

  String _question() {
    final files = AppScope.of(context).files;
    final name = widget.node.ref!;
    final docs = files.folderDocs(name);
    final users = {
      for (final d in docs)
        for (final w in files.usersOf(d.path)) w.name,
    };
    final what = docs.isEmpty
        ? 'Delete the folder $name?'
        : 'Delete the folder $name and its ${plural(docs.length, 'document', 'documents')}?';
    return users.isEmpty ? what : '$what They also leave ${users.join(', ')}.';
  }

  @override
  Widget build(BuildContext context) {
    if (!_confirming) {
      return Align(
        alignment: Alignment.centerLeft,
        child: AppButton(
          'Delete folder…',
          onPressed: () => setState(() => _confirming = true),
        ),
      );
    }
    return ConfirmBox(
      text: _question(),
      onCancel: () => setState(() => _confirming = false),
      onConfirm: () {
        setState(() => _confirming = false);
        AppScope.of(context).files.deleteFolder(widget.node.ref!);
      },
    );
  }
}

class _ChildRow extends StatelessWidget {
  const _ChildRow(this.node);

  final FileNode node;

  @override
  Widget build(BuildContext context) {
    final files = AppScope.of(context).files;
    final t = Tokens.of(context);
    return Tappable(
      label: node.name,
      onTap: () => files.reveal(node.path),
      radius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(
          children: [
            AppIcon(
              node.kind.isFolder ? 'folder' : 'doc',
              size: IconSize.xs,
              color: t.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.sans(14, color: t.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewFolder extends StatefulWidget {
  const _NewFolder();

  @override
  State<_NewFolder> createState() => _NewFolderState();
}

class _NewFolderState extends State<_NewFolder> {
  final _name = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _cancel() => setState(() {
    _adding = false;
    _name.clear();
  });

  Future<void> _create() async {
    final name = _name.text;
    _cancel();
    await AppScope.of(context).files.createFolder(name);
  }

  @override
  Widget build(BuildContext context) => _adding
      ? InlineInput(
          controller: _name,
          label: 'New folder name',
          hint: 'Folder name',
          height: 36,
          onSubmit: _create,
          onCancel: _cancel,
        )
      : Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            'New folder',
            onPressed: () => setState(() => _adding = true),
          ),
        );
}

/// The library documents workspace [slug] does not use yet, each with a way to attach it.
class _Attach extends StatelessWidget {
  const _Attach(this.slug);

  final String slug;

  @override
  Widget build(BuildContext context) {
    final files = AppScope.of(context).files;
    final t = Tokens.of(context);
    final used = {
      for (final d in files.detail(slug)?.documents ?? const []) d.path,
    };
    final free = [
      for (final folder in files.library)
        for (final doc in folder.files)
          if (!used.contains(doc.path)) doc,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Attach from the library'),
        const SizedBox(height: 8),
        if (free.isEmpty)
          Text(
            'Every library document is attached already.',
            style: Type.sans(13.5, color: t.muted),
          ),
        for (final doc in free)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${doc.folder} / ${doc.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sans(14, color: t.ink),
                  ),
                ),
                const SizedBox(width: 8),
                IconBtn(
                  'plus',
                  tooltip: 'Attach ${doc.title}',
                  box: 30,
                  size: IconSize.xs,
                  onPressed: () => files.attach(slug, doc.path),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
