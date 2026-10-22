import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../core/sources.dart';
import '../app_scope.dart';
import '../layout.dart';
import '../settings/rows.dart';
import '../list_detail.dart';
import '../sources/add_source.dart';
import '../sources/sources_panel.dart';
import '../sources/test_question.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/list_row.dart';
import '../widgets/scroll_fades.dart';
import '../widgets/upload_queue.dart';
import 'save_file.dart';
import 'section_view.dart';
import 'text_viewer.dart';

/// The open workspace's Documents as a page, which [Pane.documents] shows on a wide window: its
/// title with Add a file, Add a link and Paste text, then its documents in a list, each with its
/// switch, and Test a question, beside the text the server read from the one chosen, with
/// Download and Remove from workspace. The first is chosen until another is, and a citation's
/// flash chooses its file. Narrower, the list fills the page and a document's text takes its
/// place, with a way back to the list.
class DocumentsPane extends StatelessWidget {
  const DocumentsPane({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.chat, scope.sources]),
      builder: (context, _) => switch (scope.chat.activeSlug) {
        // What waits for Add, a question and the choice belong to one workspace.
        final slug? => _Documents(key: ValueKey(slug)),
        null => const Blank('No workspace is open.'),
      },
    );
  }
}

class _Documents extends StatefulWidget {
  const _Documents({super.key});

  @override
  State<_Documents> createState() => _DocumentsState();
}

class _DocumentsState extends State<_Documents> {
  /// The path of the document chosen, or null for the first.
  String? _chosen;

  /// Whether the chosen document's text fills a narrow page, in place of the list.
  bool _reading = false;

  /// The flash last seen, so a new one chooses its file once.
  String? _flashSeen;

  /// Chooses the document at [path], showing its text.
  void _choose(String path) => setState(() {
    _chosen = path;
    _reading = true;
  });

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sources = scope.sources;
    final files = sources.files;
    final flashed = sources.flashed;
    if (flashed != null && flashed != _flashSeen) {
      _flashSeen = flashed;
      if (files.any((f) => f.path == flashed)) _chosen = flashed;
    }
    final chosen =
        files.where((f) => f.path == _chosen).firstOrNull ?? files.firstOrNull;
    // The first stays chosen when the list's order changes, as a switch moves it.
    _chosen = chosen?.path;
    final list = _list(context, files, chosen);
    // The text is read only where it shows: beside the list, or in its place.
    final Widget body = switch ((Wide.split(context), chosen)) {
      (true, final chosen?) => ListDetail(
        list: list,
        detail: _DocText(chosen, key: ValueKey(chosen.path)),
      ),
      (false, final chosen?) when _reading => _DocText(
        chosen,
        key: ValueKey(chosen.path),
        onBack: () => setState(() => _reading = false),
      ),
      _ => list,
    };
    final page = Column(
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
            child: body,
          ),
        ),
      ],
    );
    if (chosen == null) return page;
    return RemoveDocPopup(
      chosen,
      onRemoved: () => setState(() => _reading = false),
      child: page,
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

  /// The documents in a card, each with its switch, then Test a question.
  Widget _list(
    BuildContext context,
    List<SourceFile> files,
    SourceFile? chosen,
  ) {
    final scope = AppScope.of(context);
    final slug = scope.chat.activeSlug;
    return ScrollFades(
      child: ListView(
        children: [
          if (files.isEmpty && scope.sources.loading)
            const ListCard([CardNote('Loading…')])
          else if (files.isNotEmpty)
            ListCard([
              for (final file in files)
                ListRow(
                  key: ValueKey(file.path),
                  lead: TypeTile(file),
                  title: file.title,
                  about: file.meta,
                  heard:
                      '${[file.title, if (file.meta.isNotEmpty) file.meta].join(', ')}. '
                      'Show its text',
                  selected: file.path == chosen?.path,
                  onTap: () => _choose(file.path),
                  trailing: Padding(
                    padding: const EdgeInsets.only(left: 4, right: 12),
                    child: AppSwitch(
                      value: file.on,
                      label: 'Use ${file.title} in answers',
                      tooltip: 'Use in answers',
                      onChanged: (_) => scope.sources.toggle(file),
                    ),
                  ),
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
    );
  }
}

/// The text the server read from [file] in a card: its name, kind and size and whether answers
/// use it, with Download, over the text and Remove from workspace. [onBack] adds a way back to
/// the list. It reads the text as it is first built, keyed by the document, so another document
/// chosen builds it afresh and a list's rebuild leaves it be.
class _DocText extends StatefulWidget {
  const _DocText(this.file, {super.key, this.onBack});

  final SourceFile file;
  final VoidCallback? onBack;

  @override
  State<_DocText> createState() => _DocTextState();
}

class _DocTextState extends State<_DocText> {
  late final Future<String> _text = AppScope.of(context).files
      .textOf(widget.file.path);

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final file = widget.file;
    return DetailCard(
      title: file.title,
      about: Text(
        [
          file.tile,
          if (file.size.isNotEmpty) file.size,
          usedLine(file),
        ].join(' · '),
        style: Type.note(t.ink),
      ),
      back: 'Back to Documents',
      onBack: widget.onBack,
      actions: [
        IconBtn.header(
          'download',
          tooltip: 'Download the extracted text',
          // The text read is kept, so this asks the server again only once it is let go of.
          onPressed: () => saveText(
            context,
            file.title,
            () => scope.files.textOf(file.path),
            report: scope.sources.report,
          ),
        ),
      ],
      child: ScrollFades(
        color: t.tile,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Sizes.column),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: t.ground,
                        borderRadius: BorderRadius.circular(Sizes.notice),
                      ),
                      child: FutureBuilder(
                        future: _text,
                        builder: (context, read) => switch (read) {
                          AsyncSnapshot(:final String data) => SelectableText(
                            data,
                            style: Type.body(t.ink),
                          ),
                          AsyncSnapshot(error: ApiException(:final message)) =>
                            SelectableText(message, style: Type.body(t.muted)),
                          _ => Text('Loading…', style: Type.body(t.muted)),
                        },
                      ),
                    ),
                    Text(
                      'The text the server read from this document.',
                      style: Type.note(t.ink),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        'Remove from workspace',
                        danger: true,
                        compact: true,
                        onPressed: () =>
                            scope.shell.togglePopup(Popup.removeDoc),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
