import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/files.dart';
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
import 'doc_views.dart';

/// The Essentials view's sections in the sidebar, each with a hint such as how many documents
/// are switched on.
class EssentialsList extends StatelessWidget {
  const EssentialsList({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final files = scope.files;
    final sources = scope.sources;
    return ListenableBuilder(
      listenable: Listenable.merge([files, sources]),
      builder: (context, _) => ListView(
        children: [
          for (final section in FilesSection.values)
            _SectionRow(
              section,
              hint: section == FilesSection.documents && sources.read != null
                  ? '${sources.onCount} on'
                  : '',
              selected: files.section == section,
            ),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow(this.section, {required this.hint, required this.selected});

  final FilesSection section;
  final String hint;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tappable(
        label: hint.isEmpty ? section.title : '${section.title}, $hint',
        selected: selected,
        onTap: () {
          scope.files.openSection(section);
          scope.shell.closeSide();
        },
        radius: BorderRadius.circular(8),
        color: selected ? t.sel : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    section.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sans(
                      14,
                      weight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: t.ink,
                    ),
                  ),
                ),
                if (hint.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(hint, style: Type.sans(12, color: t.muted)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A page of the Essentials view: its paragraphs at most 640 px wide, scrolling.
class _Page extends StatelessWidget {
  const _Page(this.children);

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
class EssentialDocs extends StatefulWidget {
  const EssentialDocs({super.key});

  @override
  State<EssentialDocs> createState() => _EssentialDocsState();
}

class _EssentialDocsState extends State<EssentialDocs> {
  bool _testing = false;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sources = scope.sources;
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: sources,
      builder: (context, _) {
        final docs = sources.files;
        return _Page([
          Text(
            'Answers draw on the ones switched on. This is the same list as Documents beside a chat.',
            style: Type.sans(14, color: t.ink2, height: 1.5),
          ),
          const SizedBox(height: 14),
          UploadQueue(
            onSend: sources.upload,
            onProblem: sources.report,
            trigger: (browse) => AddSource(
              buttons: true,
              leading: AppButton('Add a file', onPressed: browse),
              trailing: _testing
                  ? null
                  : _LinkButton(
                      'Test a question',
                      // As tall as the buttons, so it sits level with their first row.
                      height: ScreenClass.ofContext(context).isPhone ? 44 : 40,
                      onTap: () => setState(() => _testing = true),
                    ),
            ),
          ),
          if (_testing) ...[
            const SizedBox(height: 12),
            TestQuestion(onDone: () => setState(() => _testing = false)),
          ],
          if (sources.sending case final name?) ...[
            const SizedBox(height: 10),
            HelpText('Adding $name…', status: true),
          ],
          for (final problem in sources.problems) ...[
            const SizedBox(height: 10),
            AlertBox(AlertKind.bad, problem.title, text: problem.text),
          ],
          const SizedBox(height: 14),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: t.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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
              ],
            ),
          ),
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

/// One document: its type, name and size, whether it is pinned, its switch, and View extracted
/// text, which moves under the name when the row is narrow.
class _DocRow extends StatelessWidget {
  const _DocRow(this.doc, {super.key});

  final SourceFile doc;

  /// The narrowest row with View extracted text beside the switch.
  static const _wide = 480.0;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final view = _LinkButton(
      'View extracted text',
      semanticLabel: 'View extracted text of ${doc.title}',
      onTap: () => scope.files.viewText(doc.path, doc.title),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.line2)),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= _wide;
          return Row(
            children: [
              TypeTile(doc),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.sans(
                        14,
                        weight: FontWeight.w500,
                        color: t.ink,
                      ),
                    ),
                    if (doc.filesMeta.isNotEmpty)
                      Text(
                        doc.filesMeta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Type.sans(12, color: t.muted),
                      ),
                    if (!wide)
                      Transform.translate(
                        offset: const Offset(-8, 0),
                        child: view,
                      ),
                  ],
                ),
              ),
              if (doc.pinned) ...[
                const SizedBox(width: 12),
                const AppBadge('Pinned', kind: BadgeKind.accent),
              ],
              const SizedBox(width: 12),
              AppSwitch(
                value: doc.on,
                label: 'Use ${doc.title} in answers',
                tooltip: 'Use in answers',
                onChanged: (_) => scope.sources.toggle(doc),
              ),
              if (wide) ...[const SizedBox(width: 12), view],
            ],
          );
        },
      ),
    );
  }
}

/// A small button that is only its words, in the accent.
class _LinkButton extends StatelessWidget {
  const _LinkButton(
    this.label, {
    required this.onTap,
    this.semanticLabel,
    this.height = 32,
  });

  final String label;
  final VoidCallback onTap;

  /// The least height, with the words in its middle.
  final double height;

  /// What a screen reader hears, when [label] alone is not enough, as in a list.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Tappable(
    label: semanticLabel ?? label,
    onTap: onTap,
    radius: BorderRadius.circular(6),
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            label,
            style: Type.sans(13, color: Tokens.of(context).accent),
          ),
        ),
      ),
    ),
  );
}

/// The text the server read from the document View extracted text opened, under the way back to
/// the documents.
class TextViewer extends StatelessWidget {
  const TextViewer({super.key});

  @override
  Widget build(BuildContext context) {
    final files = AppScope.of(context).files;
    return _Page([
      Align(
        alignment: Alignment.centerLeft,
        child: TextAction('back', 'Documents', files.closeText),
      ),
      const SizedBox(height: 12),
      if (files.contentLoading)
        Text(
          'Loading…',
          style: Type.sans(13.5, color: Tokens.of(context).muted),
        )
      else if (files.doc case final doc?)
        DocBodyView(doc),
    ]);
  }
}

/// Where the files an agent made in the open workspace are: under the answers that made them.
/// The server has no call that lists them, so nothing is listed here.
class CreatedFiles extends StatelessWidget {
  const CreatedFiles({super.key, required this.workspace});

  /// The open workspace's name.
  final String workspace;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return _Page([
      Text(
        'Files the agent makes while answering in $workspace appear under the answer that '
        'made them, where each one can be saved.',
        style: Type.sans(14, color: t.ink2, height: 1.5),
      ),
      const SizedBox(height: 12),
      Text(
        'The server has no list of them all, so they are not gathered here.',
        style: Type.sans(12.5, color: t.muted, height: 1.45),
      ),
    ]);
  }
}
