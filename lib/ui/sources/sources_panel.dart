import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/sources.dart';
import '../app_scope.dart';
import '../settings/rows.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/upload_queue.dart';
import '../widgets/rise.dart';
import '../widgets/sheet.dart';
import '../widgets/tappable.dart';
import 'add_source.dart';
import 'test_question.dart';

/// The active workspace's files, which people see as Documents: switch them on and off, open
/// the text the server read from each, add them, and test what a question finds in them.
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

/// What waits, is being added or went wrong, and the undo of a removal, under the ways to add.
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
    if (sources.removed case final file?) ...[
      const SizedBox(height: 10),
      UndoBar('Removed ${file.title}', onUndo: sources.undo),
    ],
  ];
}

/// The sheet: what the switches mean, the files in a card, each with its switch, then Add a
/// file, Add a link and Paste text as buttons, and Test a question. It is as tall as what it
/// holds.
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
    return CustomScrollView(
      shrinkWrap: true,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CardCaption(
                files.isEmpty && !sources.loading
                    ? 'No documents in this workspace yet.'
                    : 'Answers draw on the ones switched on.',
              ),
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
              count: files.length,
              keyOf: (i) => ValueKey(files[i].path),
              row: (context, i) => Rise(
                child: _FileRow(
                  files[i],
                  flashed: sources.flashed == files[i].path,
                ),
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

/// A file in the sheet's card: its type, name and size, and its switch. Tapped, it shows the
/// text the server read from it in the workspace's pages, where it is downloaded or removed.
class _FileRow extends StatelessWidget {
  const _FileRow(this.file, {required this.flashed});

  final SourceFile file;
  final bool flashed;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    // A citation's flash fills the row.
    return AnimatedContainer(
      duration: motion(context, const Duration(milliseconds: 300)),
      color: flashed ? t.accentSoft : Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: Tappable(
              label: 'View extracted text of ${file.title}',
              excludeSemantics: false,
              onTap: () {
                scope.shell.showDocText();
                unawaited(scope.files.viewText(file.path, file.title));
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: Sizes.cardRow),
                padding: const EdgeInsets.only(left: FieldCard.inset),
                child: SourceRow(file, meta: file.meta),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, right: FieldCard.inset),
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
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.body(t.ink),
              ),
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

/// A document's type on a small tile, such as `PDF`. Switched off, only the tile fades: the name
/// beside it stays at full strength.
class TypeTile extends StatelessWidget {
  /// [file]'s type, faded while it is switched off.
  TypeTile(SourceFile file, {super.key}) : label = file.tile, on = file.on;

  /// The type [label], such as `PDF`, of a file that is not a document.
  const TypeTile.label(this.label, {super.key}) : on = true;

  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Opacity(
      opacity: on ? 1 : 0.5,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.accentSoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: Type.caption(t.accent, weight: FontWeight.w700),
        ),
      ),
    );
  }
}
