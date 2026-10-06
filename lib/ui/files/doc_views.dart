import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/files.dart';
import '../../core/server_models.dart';
import '../app_scope.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/confirm_box.dart';
import '../widgets/controls.dart';

/// A library document: who uses it, moving and deleting it, its details and text.
class LibraryDocView extends StatefulWidget {
  const LibraryDocView(this.node, {super.key});

  final FileNode node;

  @override
  State<LibraryDocView> createState() => _LibraryDocViewState();
}

class _LibraryDocViewState extends State<LibraryDocView> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final files = AppScope.of(context).files;
    final t = Tokens.of(context);
    final path = widget.node.ref!;
    final folder = docFolder(path);
    final users = files.usersOf(path);
    final others = [
      for (final f in files.library)
        if (f.name != folder) f.name,
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          users.isEmpty
              ? 'No workspace uses it.'
              : 'Used by ${[for (final w in users) w.name].join(', ')}.',
          style: Type.sans(14, color: t.muted),
        ),
        const SizedBox(height: 16),
        if (_confirming)
          ConfirmBox(
            text: users.isEmpty
                ? 'Delete ${widget.node.name} from the library?'
                : 'Delete ${widget.node.name} from the library and from ${plural(users.length, 'workspace', 'workspaces')}?',
            onCancel: () => setState(() => _confirming = false),
            onConfirm: () {
              setState(() => _confirming = false);
              files.deleteFromLibrary(path);
            },
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final name in others)
                AppButton(
                  'Move to $name',
                  onPressed: () => files.move(path, name),
                ),
              AppButton(
                'Delete…',
                onPressed: () => setState(() => _confirming = true),
              ),
            ],
          ),
        const SizedBox(height: 20),
        if (files.doc case final doc?) DocBodyView(doc),
      ],
    );
  }
}

/// A workspace's link to a library document: pinning, detaching, and the document itself.
class DocLinkView extends StatelessWidget {
  const DocLinkView(this.node, {super.key});

  final FileNode node;

  @override
  Widget build(BuildContext context) {
    final files = AppScope.of(context).files;
    final t = Tokens.of(context);
    final slug = node.slug!;
    final path = node.ref!;
    final link = files.docIn(slug, path);
    final workspace = files.detail(slug)?.name ?? slug;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'A link to library/$path. Detaching it from $workspace leaves it in the library.',
          style: Type.sans(14, color: t.muted),
        ),
        const SizedBox(height: 16),
        if (link != null) ...[
          Row(
            children: [
              AppSwitch(
                value: link.pinned,
                label: 'Pin ${node.name}',
                onChanged: (on) => files.pin(slug, path, pinned: on),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pinned: its whole text is always in context.',
                  style: Type.sans(14, color: t.ink),
                ),
              ),
            ],
          ),
          if (link.watched) ...[
            const SizedBox(height: 8),
            Text(
              'Watched: the server re-reads it from its source.',
              style: Type.sans(14, color: t.ink),
            ),
          ],
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppButton(
              'Open in library',
              onPressed: () => files.reveal(libraryPath(path)),
            ),
            AppButton('Detach', onPressed: () => files.detach(slug, path)),
          ],
        ),
        const SizedBox(height: 20),
        if (files.doc case final doc?) DocBodyView(doc),
      ],
    );
  }
}

/// A document's details and its text, or why there is no text.
class DocBodyView extends StatelessWidget {
  const DocBodyView(this.doc, {super.key});

  final DocBody doc;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final MapEntry(:key, :value) in doc.details.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${docDetailLabels[key] ?? key}: ',
                    style: Type.sans(13.5, color: t.muted),
                  ),
                  TextSpan(
                    text: value,
                    style: Type.sans(13.5, color: t.ink),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 14),
        const SectionLabel('Text'),
        const SizedBox(height: 8),
        if (doc.text case final text?)
          SelectableText(text, style: Type.mono(13, color: t.ink, height: 1.5))
        else
          Text(
            'The server did not send this document\'s text.',
            style: Type.sans(13.5, color: t.muted),
          ),
        const SizedBox(height: 8),
        Text(
          'The server keeps only the text it read, never the uploaded file.',
          style: Type.sans(12.5, color: t.muted),
        ),
      ],
    );
  }
}
