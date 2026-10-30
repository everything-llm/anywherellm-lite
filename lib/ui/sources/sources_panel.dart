import 'package:flutter/material.dart';

import '../../core/sources.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../state/sources_controller.dart';
import '../settings/rows.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/tappable.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/upload_queue.dart';
import '../widgets/rise.dart';
import '../widgets/sheet.dart';
import 'add_source.dart';
import 'test_question.dart';

/// The server's library, which people see as Documents: switch each document on and off for the
/// active workspace, open one's details, add documents, and test what a question finds in them.
class SourcesPanel extends StatelessWidget {
  const SourcesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return SheetFrame(
      title: 'Documents',
      onClose: scope.shell.closeSources,

      child: ListenableBuilder(
        listenable: scope.sources,
        // Built afresh on each change, never const, so the files shown follow Sources.
        builder: (context, _) => _Body(scope.sources.files),
      ),
    );
  }
}

/// What waits, is being added or went wrong, under the ways to add.
List<Widget> documentNotices(BuildContext context) {
  final sources = AppScope.of(context).sources;
  final t = Tokens.of(context);
  return [
    if (sources.sending case final name?) ...[
      const SizedBox(height: 10),
      Text('Adding $name…', style: Type.note(t.ink)),
    ],
    for (final problem in sources.problems) ...[
      const SizedBox(height: 10),
      AlertBox.notice(AlertKind.bad, problem),
    ],
  ];
}

/// The line over Documents' card: what its switches mean, or that the library is empty.
String documentsCaption(SourcesController sources) =>
    sources.files.isEmpty && !sources.loading
    ? 'No documents on the server yet.'
    : 'Answers draw on the ones switched on.';

/// What Documents' card holds, top to bottom: the [files], each folder's name, a [String], over
/// its files once they are in more than one folder.
List<Object> documentItems(List<SourceFile> files) {
  final folders = byFolder(files);
  if (folders.length < 2) return files;
  return [
    for (final (folder, inIt) in folders) ...[folder, ...inIt],
  ];
}

/// Whether the item of Documents' card at [i] has a hairline over it: every one but the first,
/// and a file under its folder's name.
bool documentRuled(List<Object> items, int i) =>
    i > 0 && items[i - 1] is! String;

/// The item of Documents' card [item]: a folder's name, or a file's row, lit while it is the
/// one whose details show beside the list ([chosen]) or a citation [flashed] it.
Widget documentItem(
  Object item, {
  required bool flashed,
  bool chosen = false,
}) => switch (item) {
  final SourceFile file => DocumentRow(
    file,
    key: ValueKey(file.path),
    flashed: flashed,
    chosen: chosen,
  ),
  final folder => FolderHeading('$folder', key: ValueKey(('folder', folder))),
};

/// A library folder's name over its documents in Documents' card, small, in ink.
class FolderHeading extends StatelessWidget {
  const FolderHeading(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(FieldCard.inset, 12, FieldCard.inset, 4),
    child: Semantics(
      header: true,
      child: Text(name, style: Type.caption(Tokens.of(context).ink)),
    ),
  );
}

/// The sheet: what the switches mean, the library in a card, each document with its switch,
/// under its folder's name once there is more than one, then Add a file, Add a link and Paste
/// text as buttons, and Test a question. It is as tall as what it holds.
class _Body extends StatelessWidget {
  const _Body(this.files);

  /// The files as Sources has them now.
  final List<SourceFile> files;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sources = scope.sources;
    final slug = scope.chat.activeSlug;
    final card = files.isNotEmpty || sources.loading;
    final items = documentItems(files);
    return CustomScrollView(
      shrinkWrap: true,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CardCaption(documentsCaption(sources)),
              ...documentNotices(context),
              const SizedBox(height: 16),
            ],
          ),
        ),
        if (card) ...[
          if (files.isEmpty)
            SliverToBoxAdapter(child: FieldCard(const [CardNote('Loading…')]))
          else
            SliverFieldCard(
              count: items.length,
              keyOf: (i) => switch (items[i]) {
                final SourceFile file => ValueKey(file.path),
                final folder => ValueKey(('folder', folder)),
              },
              ruledAt: (i) => documentRuled(items, i),
              row: (context, i) => Rise(
                child: switch (items[i]) {
                  final SourceFile file => documentItem(
                    file,
                    flashed: sources.flashed == file.path,
                  ),
                  final folder => documentItem(folder, flashed: false),
                },
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UploadQueue(
                key: ValueKey(('queue', slug)),
                onSend: sources.upload,
                onProblem: sources.report,
                types: sources.acceptedTypes,
                trigger: (browse) => AddSource(
                  key: ValueKey(('add', slug)),
                  leading: AppButton('Add a file', onPressed: browse),
                ),
              ),
              const SizedBox(height: 4),
              TestQuestion(
                key: ValueKey(('test', slug)),
                trigger: (open) => Align(
                  alignment: Alignment.centerLeft,
                  child: open == null
                      ? const SizedBox.shrink()
                      : TextAction('search', 'Test a question', open),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A file in Documents' card: its type, name and the line under it, which open its details, then
/// its switch, which puts it in the open workspace's answers or takes it out. A citation's
/// [flashed], or being the one whose details show beside the list ([chosen]), fills it.
class DocumentRow extends StatelessWidget {
  const DocumentRow(
    this.file, {
    super.key,
    required this.flashed,
    this.chosen = false,
  });

  final SourceFile file;
  final bool flashed;
  final bool chosen;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return AnimatedContainer(
      duration: motion(context, const Duration(milliseconds: 300)),
      color: flashed || chosen ? t.accentSoft : Colors.transparent,
      constraints: const BoxConstraints(minHeight: Sizes.cardRow),
      child: Row(
        children: [
          Expanded(
            child: Tappable(
              label: 'Details of ${file.title}',
              selected: chosen ? true : null,
              onTap: () => scope.shell.openDocument(file.storedName),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Sizes.cardRow),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(FieldCard.inset, 8, 0, 8),
                  child: Row(
                    spacing: 8,
                    children: [
                      Expanded(child: SourceRow(file, meta: file.meta)),
                      AppIcon('chevron', size: IconSize.xs, color: t.muted),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // In a 52 column at the card's inset, as a [FieldRow]'s switch is.
          Padding(
            padding: const EdgeInsets.only(left: 6, right: FieldCard.inset),
            child: AppSwitch(
              value: file.on,
              label: 'Use ${file.title} in answers',
              tooltip: 'Use in answers',
              onChanged: (_) => scope.sources.toggle(file),
            ),
          ),
        ],
      ),
    );
  }
}

/// A document's row: its [TypeTile], then its title with [meta] under it.
class SourceRow extends StatelessWidget {
  SourceRow(SourceFile file, {super.key, required this.meta})
    : tile = TypeTile(file),
      title = file.title;

  final Widget tile;
  final String title;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(
      spacing: 14,
      children: [
        tile,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Type.body(t.ink)),
              if (meta.isNotEmpty)
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.note(t.ink),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A document's type on a small tile, such as `PDF`: in ink on a sunken well, as House UI's
/// row leads are, at least 48 wide and 40 tall, room for a four letter type such as DOCX so
/// the names beside a list of them line up, and wider when its word needs it, so a long type or
/// large text is never cut. It looks the same switched on or off, never faded: the line under the name says
/// whether answers use it.
class TypeTile extends StatelessWidget {
  /// [file]'s type.
  TypeTile(SourceFile file, {super.key}) : label = file.tile;

  /// The type [label], such as `PDF`, of a file that is not a document.
  const TypeTile.label(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.sunken,
          borderRadius: BorderRadius.circular(8),
        ),
        // As large as its word and no larger, centred in the least size when that is more.
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Type.caption(t.ink, weight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}
