import 'package:flutter/material.dart';

import '../../core/sources.dart';
import '../app_scope.dart';
import '../layout.dart';
import '../settings/rows.dart';
import '../list_detail.dart';
import '../sources/add_source.dart';
import '../sources/document_details.dart';
import '../sources/sources_panel.dart';
import '../sources/test_question.dart';
import '../widgets/buttons.dart';
import '../widgets/scroll_fades.dart';
import '../widgets/upload_queue.dart';
import 'section_view.dart';

/// The open workspace's Documents as a page, which [Pane.documents] shows on a wide window: its
/// title with Add a file, Add a link and Paste text, then the library in a card, each document
/// with its switch, under its folder's name, as the Documents sheet has them, and Test a
/// question. A document's details show beside the list, or, on a window too narrow for both, in
/// its place, with Back. A citation's flash fills its file's row for a moment.
class DocumentsPane extends StatelessWidget {
  const DocumentsPane({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.chat, scope.sources, scope.shell]),
      builder: (context, _) => switch (scope.chat.activeSlug) {
        // What waits for Add and a question belong to one workspace.
        final slug? => _Documents(key: ValueKey(slug)),
        null => const Blank('No workspace is open.'),
      },
    );
  }
}

class _Documents extends StatelessWidget {
  const _Documents({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final files = scope.sources.files;
    final open = scope.shell.document;
    final split = Wide.split(context);
    // Too narrow for the list beside them, the details fill the pane, with Back.
    if (open != null && !split) {
      return DocumentDetailsPage(open, key: ValueKey(('details', open)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, files),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: documentNotices(context),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: open == null
                ? _list(context, files)
                : ListDetail(
                    list: _list(context, files, chosen: open),
                    detail: DocumentDetailsCard(
                      open,
                      key: ValueKey(('details', open)),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// The page's title and what the switches mean, beside the ways to add a document, whose form
  /// opens under them; and a way back where no sidebar shows the way out.
  Widget _header(BuildContext context, List<SourceFile> files) {
    final scope = AppScope.of(context);
    final slug = scope.chat.activeSlug;
    final title = PaneTitle(
      'Documents',
      about: [
        ?scope.chat.active?.name,
        documentsCaption(scope.sources),
      ].join(' · '),
    );
    return PaneHeader(
      back: scope.shell.overPages
          ? 'Back to the workspace'
          : 'Back to the chat',
      onBack: scope.shell.closePane,
      child: UploadQueue(
        key: ValueKey(('queue', slug)),
        onSend: scope.sources.upload,
        onProblem: scope.sources.report,
        types: scope.sources.acceptedTypes,
        trigger: (browse) => AddSource(
          key: ValueKey(('add', slug)),
          leading: AppButton('Add a file', compact: true, onPressed: browse),
          place: (shown, form) => form
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 12,
                  children: [
                    title,
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: Sizes.column),
                      child: shown,
                    ),
                  ],
                )
              : Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [title, shown],
                ),
        ),
      ),
    );
  }

  /// The library in a card, each document with its switch, under its folder's name, the one
  /// whose details show beside them [chosen], then Test a question, no wider than a column.
  Widget _list(BuildContext context, List<SourceFile> files, {String? chosen}) {
    final scope = AppScope.of(context);
    final sources = scope.sources;
    final slug = scope.chat.activeSlug;
    final items = documentItems(files);
    return ScrollFades(
      child: ListView(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Sizes.column),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (files.isEmpty && sources.loading)
                    FieldCard(const [CardNote('Loading…')])
                  else if (files.isNotEmpty)
                    FieldCard(ruledAt: (i) => documentRuled(items, i), [
                      for (final item in items)
                        documentItem(
                          item,
                          flashed:
                              item is SourceFile &&
                              sources.flashed == item.path,
                          chosen:
                              item is SourceFile && item.storedName == chosen,
                        ),
                    ]),
                  const SizedBox(height: 12),
                  TestQuestion(
                    key: ValueKey(('test', slug)),
                    trigger: (open) => Align(
                      alignment: Alignment.centerLeft,
                      child: open == null
                          ? const SizedBox.shrink()
                          : TextAction('search', 'Test a question', open),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
