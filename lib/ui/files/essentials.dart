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
import '../settings/rows.dart';
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
        radius: BorderRadius.circular(Sizes.row),
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
                        // As tall as the buttons, so it sits level with their first row; a
                        // phone's are 44, which a TextAction is there at least.
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

/// One document: its type, name and size, whether it is pinned, its switch, View extracted
/// text, which moves under the name when the row is narrow, and Download text.
class _DocRow extends StatelessWidget {
  const _DocRow(this.doc, {super.key});

  final SourceFile doc;

  /// The narrowest row with View extracted text beside the switch.
  static const _wide = 480.0;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    // A phone's row is the document's name, its size and its switch; tapped, it opens the text.
    if (ScreenClass.ofContext(context).isPhone) {
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
            large: true,
            trailing: [
              AppSwitch(
                value: doc.on,
                label: 'Use ${doc.title} in answers',
                large: true,
                onChanged: (_) => scope.sources.toggle(doc),
              ),
            ],
          ),
        ),
      );
    }
    final view = TextAction.plain(
      'View extracted text',
      () => scope.files.viewText(doc.path, doc.title),
      semanticLabel: 'View extracted text of ${doc.title}',
      height: 32,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= _wide;
          return SourceRow(
            doc,
            meta: doc.filesMeta,
            roomy: true,
            // Under the name, its words line up with the name's.
            below: wide
                ? null
                : Transform.translate(offset: const Offset(-6, 0), child: view),
            trailing: [
              if (doc.pinned) const AppBadge('Pinned', kind: BadgeKind.accent),
              AppSwitch(
                value: doc.on,
                label: 'Use ${doc.title} in answers',
                tooltip: 'Use in answers',
                onChanged: (_) => scope.sources.toggle(doc),
              ),
              if (wide) view,
              DownloadTextButton(doc),
            ],
          );
        },
      ),
    );
  }
}

/// The text the server read from the document View extracted text opened, under the way back to
/// the documents.
class TextViewer extends StatelessWidget {
  const TextViewer({super.key});

  @override
  Widget build(BuildContext context) {
    final files = AppScope.of(context).files;
    if (ScreenClass.ofContext(context).isPhone) return const _PhoneText();
    return EssentialsPage([
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

/// A phone's page of a document's text, under the header that names it and offers Download: its
/// kind and size, whether answers use it, the text in a card, and Remove from workspace.
class _PhoneText extends StatelessWidget {
  const _PhoneText();

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
