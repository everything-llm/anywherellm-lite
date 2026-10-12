import 'package:flutter/material.dart';

import '../../core/sources.dart';
import '../app_scope.dart';
import '../files/save_file.dart';
import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/upload_queue.dart';
import '../widgets/rise.dart';
import '../widgets/sheet.dart';
import '../widgets/side_panel.dart';
import 'add_source.dart';
import 'test_question.dart';

/// The active workspace's files, which people see as Documents: add them, switch them on and
/// off, remove them, and test what a question finds in them.
class SourcesPanel extends StatelessWidget {
  const SourcesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return SidePanel(
      title: 'Documents',
      about: 'Answers draw on the ones switched on.',
      onClose: scope.shell.closeSources,
      sheetHeight: SheetHeight.fit,
      child: ListenableBuilder(
        listenable: scope.sources,
        // Built afresh on each change, never const, so the files shown follow Sources.
        builder: (context, _) => _Body(scope.sources.files),
      ),
    );
  }
}

/// What waits, is being added or went wrong, and the undo of a removal, under the ways to add.
List<Widget> _notices(BuildContext context) {
  final sources = AppScope.of(context).sources;
  final t = Tokens.of(context);
  return [
    if (sources.sending case final name?) ...[
      const SizedBox(height: 10),
      Text('Adding $name…', style: Type.sans(12.5, color: t.muted)),
    ],
    for (final problem in sources.problems) ...[
      const SizedBox(height: 10),
      AlertBox(AlertKind.bad, problem.title, text: problem.text),
    ],
    if (sources.removed case final file?) ...[
      const SizedBox(height: 10),
      UndoBar('Removed ${file.title}', onUndo: sources.undo),
    ],
  ];
}

/// The sheet: Add a file, Add a link and Paste text as buttons, the files with a rule between
/// them, then Test a question. It is as tall as what it holds.
class _Body extends StatelessWidget {
  const _Body(this.files);

  /// The files as Sources has them now.
  final List<SourceFile> files;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sources = scope.sources;
    final slug = scope.chat.activeSlug;
    return CustomScrollView(
      shrinkWrap: true,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              UploadQueue(
                key: ValueKey(('queue', slug)),
                onSend: sources.upload,
                onProblem: sources.report,
                trigger: (browse) => AddSource(
                  key: ValueKey(('add', slug)),
                  buttons: true,
                  leading: AppButton('Add a file', onPressed: browse),
                ),
              ),
              ..._notices(context),
              const SizedBox(height: 12),
            ],
          ),
        ),
        _fileSliver(context, files),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TestQuestion(
              key: ValueKey(('test', slug)),
              trigger: (open) => Align(
                alignment: Alignment.centerLeft,
                child: open == null
                    ? const SizedBox.shrink()
                    : TextAction('search', 'Test a question', open),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The [files], or a line saying there are none yet, with a rule between them, as the design
/// canvas draws the sheet.
Widget _fileSliver(BuildContext context, List<SourceFile> files) {
  final sources = AppScope.of(context).sources;
  final t = Tokens.of(context);
  if (files.isEmpty) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          sources.loading ? 'Loading…' : 'No files yet.',
          textAlign: TextAlign.center,
          style: Type.sans(14, color: t.muted),
        ),
      ),
    );
  }
  return SliverList.separated(
    itemCount: files.length,
    separatorBuilder: (_, _) =>
        Divider(height: 1, thickness: 1, color: t.line2),
    itemBuilder: (context, i) => Rise(
      key: ValueKey(files[i].path),
      child: _FileRow(files[i], flashed: sources.flashed == files[i].path),
    ),
  );
}

/// A file in the sheet: 56 px tall, with its switch, download and trash.
class _FileRow extends StatelessWidget {
  const _FileRow(this.file, {required this.flashed});

  final SourceFile file;
  final bool flashed;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final row = SourceRow(
      file,
      meta: file.meta,
      trailing: [
        AppSwitch(
          value: file.on,
          label: 'Use ${file.title} in answers',
          tooltip: 'Use in answers',
          onChanged: (_) => scope.sources.toggle(file),
        ),
        DownloadTextButton(file),
        IconBtn(
          'trash',
          tooltip: 'Remove ${file.title}',
          box: 44,
          size: IconSize.small,
          dangerHover: true,
          onPressed: () => scope.sources.remove(file),
        ),
      ],
    );
    // A citation's flash fills the row, between its rules.
    return AnimatedContainer(
      duration: motion(context, const Duration(milliseconds: 300)),
      constraints: const BoxConstraints(minHeight: 56),
      alignment: Alignment.centerLeft,
      color: flashed ? t.accentbg : Colors.transparent,
      child: row,
    );
  }
}

/// A document's row: its [TypeTile], its title with [meta] under it, then each of [trailing],
/// such as its switch. [roomy] is how the workspace's Documents page draws it: wider gaps, and
/// [meta] on up to two lines.
class SourceRow extends StatelessWidget {
  SourceRow(
    SourceFile file, {
    super.key,
    required this.meta,
    required this.trailing,
    this.roomy = false,
  }) : tile = TypeTile(file),
       title = file.title;

  final Widget tile;
  final String title;
  final String meta;
  final List<Widget> trailing;
  final bool roomy;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final gap = roomy ? 12.0 : 10.0;
    return Row(
      children: [
        tile,
        SizedBox(width: gap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.sans(14.5, weight: FontWeight.w500, color: t.ink),
              ),
              if (meta.isNotEmpty)
                Text(
                  meta,
                  maxLines: roomy ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sans(12, color: t.muted),
                ),
            ],
          ),
        ),
        for (final widget in trailing) ...[SizedBox(width: gap), widget],
      ],
    );
  }
}

/// Saves the text the server read from [file], which is all it keeps of it, through [saveText].
/// A failure shows in [SourcesController.problems].
class DownloadTextButton extends StatelessWidget {
  const DownloadTextButton(this.file, {super.key});

  final SourceFile file;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return IconBtn(
      'download',
      tooltip: 'Download text of ${file.title}',
      box: 44,
      size: IconSize.small,
      onPressed: () => saveText(
        context,
        file.title,
        () => scope.files.textOf(file.path),
        report: scope.sources.report,
      ),
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
        width: 32,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.accentbg,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: Type.sans(
            9.5,
            weight: FontWeight.w600,
            color: t.accent,
            letterSpacing: 9.5 * 0.03,
          ),
        ),
      ),
    );
  }
}
