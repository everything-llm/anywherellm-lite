import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/sources.dart';
import '../app_scope.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';
import '../widgets/tappable.dart';
import '../widgets/upload_queue.dart';
import '../sources/add_source.dart';
import '../sources/sources_panel.dart';
import '../sources/test_question.dart';
import '../settings/rows.dart';

/// A page of the Essentials view: its paragraphs at most 640 px wide, scrolling.
class EssentialsPage extends StatelessWidget {
  const EssentialsPage(this.children, {super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ],
  );
}

/// The open workspace's documents, the same list as the Documents panel beside a chat: add one,
/// switch each on or off, test a question, and view the text the server read from each.
class EssentialDocs extends StatelessWidget {
  const EssentialDocs({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sources = scope.sources;
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: sources,
      builder: (context, _) {
        final docs = sources.files;
        return EssentialsPage([
          Text(
            'Answers draw on the ones switched on. This is the same list as Documents beside a chat.',
            style: Type.sans(14, color: t.ink2, height: 1.5),
          ),
          const SizedBox(height: 14),
          TestQuestion(
            trigger: (test) => UploadQueue(
              onSend: sources.upload,
              onProblem: sources.report,
              trigger: (browse) => AddSource(
                buttons: true,
                leading: AppButton('Add a file', onPressed: browse),
                trailing: test == null
                    ? null
                    : TextAction.plain(
                        'Test a question',
                        test,
                        // A TextAction is at least 44 tall, as the buttons' row is.
                        height: 40,
                      ),
              ),
            ),
          ),
          if (sources.sending case final name?) ...[
            const SizedBox(height: 10),
            HelpText('Adding $name…', status: true),
          ],
          for (final problem in sources.problems) ...[
            const SizedBox(height: 10),
            AlertBox(AlertKind.bad, problem.title, text: problem.text),
          ],
          const SizedBox(height: 14),
          FieldCard([
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                docs.isEmpty
                    ? sources.loading
                          ? 'Loading…'
                          : 'No documents yet.'
                    : '${plural(docs.length, 'document', 'documents')}, '
                          '${sources.onCount} used in answers',
                style: Type.sans(12, color: t.muted),
              ),
            ),
            for (final doc in docs) _DocRow(doc, key: ValueKey(doc.path)),
          ]),
          const SizedBox(height: 14),
          Text(
            'The server keeps only the text it read from each one, never the uploaded file.',
            style: Type.sans(12.5, color: t.muted, height: 1.45),
          ),
        ]);
      },
    );
  }
}

/// One document: its type, name, size and switch; tapped, it opens the text the server read.
class _DocRow extends StatelessWidget {
  const _DocRow(this.doc, {super.key});

  final SourceFile doc;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Tappable(
      label: 'View extracted text of ${doc.title}',
      onTap: () => scope.files.viewText(doc.path, doc.title),
      excludeSemantics: false,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.only(left: FieldCard.inset, right: 8),
        child: SourceRow(
          doc,
          meta: doc.filesMeta,
          roomy: true,
          trailing: [
            AppSwitch(
              value: doc.on,
              label: 'Use ${doc.title} in answers',
              onChanged: (_) => scope.sources.toggle(doc),
            ),
          ],
        ),
      ),
    );
  }
}

/// The page of the text the server read from the document View extracted text opened, under
/// the header that names it and offers Download: its kind and size, whether answers use it, the
/// text in a card, and Remove from workspace.
class TextViewer extends StatelessWidget {
  const TextViewer({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final files = scope.files;
    final t = Tokens.of(context);
    final path = files.reading?.path;
    final file = scope.sources.files.where((f) => f.path == path).firstOrNull;
    final text = files.doc?.text;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (file != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FieldCard.inset,
              0,
              FieldCard.inset,
              16,
            ),
            child: Row(
              spacing: 12,
              children: [
                Expanded(
                  child: Text(
                    '${file.tile} · ${file.size}',
                    style: Type.sans(13, color: t.muted),
                  ),
                ),
                Text(
                  file.on ? 'Used in answers' : 'Not used',
                  style: Type.sans(13, color: t.muted),
                ),
              ],
            ),
          ),
        if (files.contentLoading)
          Text('Loading…', style: Type.sans(14, color: t.muted))
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            decoration: BoxDecoration(
              color: t.panel,
              border: Border.all(color: t.line2),
              borderRadius: BorderRadius.circular(Sizes.phoneCard),
            ),
            child: SelectableText(
              text ?? 'The server sent no text for this document.',
              style: Type.sans(
                15.5,
                color: text == null ? t.muted : t.ink2,
                height: 1.65,
              ),
            ),
          ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'The text the server read from this document.',
            style: Type.sans(13, color: t.muted, height: 1.45),
          ),
        ),
        if (file != null) ...[
          const SizedBox(height: 20),
          ActionRow(even: true, [
            AppButton(
              'Remove from workspace',
              danger: true,
              onPressed: () {
                files.closeText();
                scope.sources.remove(file);
              },
            ),
          ]),
        ],
      ],
    );
  }
}
