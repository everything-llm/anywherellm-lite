import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/sources.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../state/shell_controller.dart';
import '../state/sources_controller.dart';
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
import 'add_source.dart';
import 'test_question.dart';

/// The active workspace's files, which people see as Documents: switch them on and off, remove
/// them, add them, and test what a question finds in them.
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
      _RemovedBar(file, key: ValueKey(('removed', file.path))),
    ],
  ];
}

/// The toast of a document just removed, with Undo and Close. The removal goes to the server
/// when it is closed, or when the toast leaves the screen, as when the sheet or the pane that
/// shows it closes.
class _RemovedBar extends StatefulWidget {
  const _RemovedBar(this.file, {super.key});

  final SourceFile file;

  @override
  State<_RemovedBar> createState() => _RemovedBarState();
}

class _RemovedBarState extends State<_RemovedBar> {
  late final SourcesController _sources;

  @override
  void initState() {
    super.initState();
    _sources = AppScope.of(context).sources;
  }

  @override
  void dispose() {
    // After the frame: settling tells Sources' listeners, which may not rebuild while the tree
    // is being torn down.
    final (sources, file) = (_sources, widget.file);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(sources.settleRemoval(of: file)),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UndoBar(
    'Removed ${widget.file.title}',
    onUndo: () => unawaited(_sources.undo()),
    onClose: () => unawaited(_sources.settleRemoval()),
  );
}

/// The sheet: what the switches mean, the files in a card, each with its switch and Remove, then
/// Add a file, Add a link and Paste text as buttons, and Test a question. It is as tall as what
/// it holds.
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
                child: DocumentRow(
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

/// A file in a card of Documents: its type, name and size, its switch, and Remove, which asks
/// first ([RemoveDocFor]). A citation's [flashed] fills it for a moment. It opens nothing.
class DocumentRow extends StatelessWidget {
  const DocumentRow(this.file, {super.key, required this.flashed});

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
      constraints: const BoxConstraints(minHeight: Sizes.cardRow),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: FieldCard.inset),
              // Heard as one: its name and size.
              child: MergeSemantics(child: SourceRow(file, meta: file.meta)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: AppSwitch(
              value: file.on,
              label: 'Use ${file.title} in answers',
              tooltip: 'Use in answers',
              onChanged: (_) => scope.sources.toggle(file),
            ),
          ),
          // Tapped in 48 around its 44, so 10 keeps it 8 from the switch.
          Padding(
            padding: const EdgeInsets.only(left: 10, right: 10),
            child: IconBtn(
              'trash',
              tooltip: 'Remove ${file.title} from workspace',
              box: 44,
              size: IconSize.small,
              onPressed: () => scope.shell.togglePopup(RemoveDocFor(file)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The question whether to take [removing]'s file out of the open workspace, over the window:
/// Remove takes it out, with a toast to undo it, and Keep leaves it. A file no longer in the
/// workspace, as after another workspace opened, is left alone.
class RemoveDocSheet extends StatelessWidget {
  const RemoveDocSheet(this.removing, {super.key});

  final RemoveDocFor removing;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final file = removing.file;
    void close() => scope.shell.closePopup(removing);
    return ModalSheet(
      title: 'Remove from workspace',
      onClose: close,
      child: SheetQuestion(
        'Remove ${file.title} from ${scope.chat.active?.name ?? 'this workspace'}? Answers '
        'stop drawing on it. The server keeps the file, to add again from Documents.',
        action: 'Remove',
        onKeep: close,
        onConfirm: () {
          close();
          final sources = scope.sources;
          if (sources.files.any((f) => f.path == file.path)) {
            unawaited(sources.remove(file));
          }
        },
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
