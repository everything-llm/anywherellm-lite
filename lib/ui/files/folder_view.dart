import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/files.dart';
import '../../core/prefs.dart';
import '../../core/server_models.dart';
import '../../core/sources.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/confirm_box.dart';
import '../widgets/upload_queue.dart';
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
        if (node.kind == NodeKind.docs) ...[
          _Docs(node),
          const SizedBox(height: 24),
          _Attach(node.slug!),
        ] else ...[
          if (node.children.isEmpty) const _Empty(),
          for (final child in node.children) _ChildRow(child),
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

/// What an empty folder says: that it is still being read, or that it is empty.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Text(
    AppScope.of(context).files.loading ? 'Loading…' : 'Empty.',
    style: Type.sans(13.5, color: Tokens.of(context).muted),
  );
}

/// A workspace's documents: those it answers from, each a link to open, and after them those
/// switched off on this device, which open in the library. Each says its size, and a switched-off
/// one that it is not used; only its icon fades.
class _Docs extends StatefulWidget {
  const _Docs(this.node);

  final FileNode node;

  @override
  State<_Docs> createState() => _DocsState();
}

class _DocsState extends State<_Docs> {
  /// What [_docs] were merged from, so another change to the prefs, such as a chat opened,
  /// merges nothing again.
  List<WorkspaceDoc>? _embedded;
  List<OffDoc>? _off;
  List<SourceFile> _docs = const [];

  List<SourceFile> _merged(List<WorkspaceDoc> embedded, List<OffDoc> off) {
    if (!identical(embedded, _embedded) || !identical(off, _off)) {
      _embedded = embedded;
      _off = off;
      _docs = mergeSources(embedded, off);
    }
    return _docs;
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final files = scope.files;
    final slug = widget.node.slug!;
    return ListenableBuilder(
      listenable: scope.prefs,
      builder: (context, _) {
        final links = {
          for (final child in widget.node.children) child.ref: child,
        };
        final docs = _merged(
          files.detail(slug)?.documents ?? const [],
          scope.prefs.offIn(slug),
        );
        if (docs.isEmpty) return const _Empty();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final doc in docs)
              if (links[doc.path] case final link?)
                _ChildRow(link, subtitle: doc.filesMeta)
              else if (!doc.on)
                _ChildRow(
                  FileNode(
                    path: libraryPath(doc.path),
                    name: doc.title,
                    kind: NodeKind.libraryDoc,
                    ref: doc.path,
                  ),
                  subtitle: doc.filesMeta,
                  faded: true,
                ),
          ],
        );
      },
    );
  }
}

class _ChildRow extends StatelessWidget {
  const _ChildRow(this.node, {this.subtitle = '', this.faded = false});

  final FileNode node;

  /// A line under the name, such as a document's size, or empty for none.
  final String subtitle;

  /// Fades the icon, for a document switched off.
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final files = AppScope.of(context).files;
    final t = Tokens.of(context);
    return Tappable(
      label: subtitle.isEmpty ? node.name : '${node.name}, $subtitle',
      onTap: () => files.reveal(node.path),
      radius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(
          children: [
            Opacity(
              opacity: faded ? 0.5 : 1,
              child: AppIcon(
                node.kind.isFolder ? 'folder' : 'doc',
                size: IconSize.xs,
                color: t.muted,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sans(14, color: t.ink),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.sans(12, color: t.muted),
                    ),
                ],
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
