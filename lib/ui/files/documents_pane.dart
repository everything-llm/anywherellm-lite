import 'package:flutter/material.dart';

import '../../core/sources.dart';
import '../app_scope.dart';
import '../layout.dart';
import '../settings/rows.dart';
import '../list_detail.dart';
import '../sources/add_source.dart';
import '../sources/sources_panel.dart';
import '../sources/test_question.dart';
import '../widgets/buttons.dart';
import '../widgets/scroll_fades.dart';
import '../widgets/upload_queue.dart';
import 'section_view.dart';

/// The open workspace's Documents as a page, which [Pane.documents] shows on a wide window: its
/// title with Add a file, Add a link and Paste text, then its documents in a card, each with its
/// switch and Remove, as the Documents sheet has them, and Test a question. A citation's flash
/// fills its file's row for a moment.
class DocumentsPane extends StatelessWidget {
  const DocumentsPane({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.chat, scope.sources]),
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
    final files = AppScope.of(context).sources.files;
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
            child: _list(context, files),
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
        files.isEmpty && !scope.sources.loading
            ? 'No documents in this workspace yet.'
            : 'Answers draw on the ones switched on.',
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

  /// The documents in a card, each with its switch and Remove, then Test a question, no wider
  /// than a column.
  Widget _list(BuildContext context, List<SourceFile> files) {
    final scope = AppScope.of(context);
    final sources = scope.sources;
    final slug = scope.chat.activeSlug;
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
                    FieldCard([
                      for (final file in files)
                        DocumentRow(
                          file,
                          key: ValueKey(file.path),
                          flashed: sources.flashed == file.path,
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
