import 'package:flutter/material.dart';

import '../../core/sources.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
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
        builder: (context, _) => ScreenClass.ofContext(context).isPhone
            ? _PhoneBody(scope.sources.files)
            : _Body(scope.sources.files),
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

/// The panel beside the chat: the drop zone, Add a link and Paste text, Test a question, then
/// the files.
class _Body extends StatelessWidget {
  const _Body(this.files);

  /// The files as Sources has them now.
  final List<SourceFile> files;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sources = scope.sources;
    final t = Tokens.of(context);
    // Everything below the heading scrolls together, so an open form or a long list of
    // files waiting to be added never pushes past the panel.
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Keyed by workspace, so what waits to be added stays with it.
              UploadQueue(
                key: ValueKey(('queue', scope.chat.activeSlug)),
                onSend: sources.upload,
                onProblem: sources.report,
              ),
              const SizedBox(height: 8),
              AddSource(key: ValueKey(('add', scope.chat.activeSlug))),
              const SizedBox(height: 4),
              TestQuestion(key: ValueKey(('test', scope.chat.activeSlug))),
              ..._notices(context),
              const SizedBox(height: 14),
            ],
          ),
        ),
        if (files.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                sources.loading ? 'Loading…' : 'No files yet.',
                textAlign: TextAlign.center,
                style: Type.sans(13.5, color: t.muted),
              ),
            ),
          )
        else
          SliverList.separated(
            itemCount: files.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, i) => Rise(
              key: ValueKey(files[i].path),
              child: _FileRow(
                files[i],
                flashed: sources.flashed == files[i].path,
              ),
            ),
          ),
      ],
    );
  }
}

/// The sheet on a phone: Add a file, Add a link and Paste text as buttons, the files with a
/// rule between them, then Test a question. It is as tall as what it holds.
class _PhoneBody extends StatelessWidget {
  const _PhoneBody(this.files);

  /// The files as Sources has them now.
  final List<SourceFile> files;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sources = scope.sources;
    final t = Tokens.of(context);
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
        if (files.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                sources.loading ? 'Loading…' : 'No files yet.',
                textAlign: TextAlign.center,
                style: Type.sans(14, color: t.muted),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: files.length,
            itemBuilder: (context, i) => Rise(
              key: ValueKey(files[i].path),
              child: _FileRow(
                files[i],
                flashed: sources.flashed == files[i].path,
                ruled: i > 0,
              ),
            ),
          ),
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

/// A file in the panel: on a phone 56 px tall, with a rule over it when [ruled], a larger
/// title, switch and trash.
class _FileRow extends StatelessWidget {
  const _FileRow(this.file, {required this.flashed, this.ruled = false});

  final SourceFile file;
  final bool flashed;
  final bool ruled;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final phone = ScreenClass.ofContext(context).isPhone;
    final row = SourceRow(
      file,
      meta: file.meta,
      large: phone,
      trailing: [
        AppSwitch(
          value: file.on,
          label: 'Use ${file.title} in answers',
          tooltip: 'Use in answers',
          onChanged: (_) => scope.sources.toggle(file),
        ),
        IconBtn(
          'trash',
          tooltip: 'Remove ${file.title}',
          box: phone ? 44 : 32,
          size: phone ? IconSize.small : IconSize.xs,
          dangerHover: true,
          onPressed: () => scope.sources.remove(file),
        ),
      ],
    );
    // A citation's flash fills the row and rings it in the accent; the ring is always there,
    // clear, so the flash moves nothing. On a phone the flash fills it alone, between its
    // rules.
    if (phone) {
      return AnimatedContainer(
        duration: motion(context, const Duration(milliseconds: 300)),
        constraints: const BoxConstraints(minHeight: 56),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: flashed ? t.accentbg : Colors.transparent,
          border: Border(
            top: BorderSide(color: ruled ? t.line2 : Colors.transparent),
          ),
        ),
        child: row,
      );
    }
    return AnimatedContainer(
      duration: motion(context, const Duration(milliseconds: 300)),
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      decoration: BoxDecoration(
        color: flashed ? t.accentbg : Colors.transparent,
        border: Border.all(color: flashed ? t.accent : Colors.transparent),
        borderRadius: BorderRadius.circular(Sizes.control),
      ),
      child: row,
    );
  }
}

/// A document's row: its [TypeTile], its title with [meta] and anything [below] under it, then
/// each of [trailing], such as its switch. [roomy] is how the Files pane draws it: a larger
/// title, wider gaps, and [meta] on up to two lines. [large] is the phone's Documents sheet: a
/// title at 14.5, with the gaps and [meta] of the panel.
class SourceRow extends StatelessWidget {
  SourceRow(
    SourceFile file, {
    super.key,
    required this.meta,
    required this.trailing,
    this.below,
    this.roomy = false,
    this.large = false,
  }) : tile = TypeTile(file),
       title = file.title;

  /// A row of a file that is not a document, with its own [tile] and [title].
  const SourceRow.label({
    super.key,
    required this.tile,
    required this.title,
    required this.meta,
    required this.trailing,
    this.below,
    this.roomy = false,
    this.large = false,
  });

  final Widget tile;
  final String title;
  final String meta;
  final List<Widget> trailing;
  final Widget? below;
  final bool roomy;
  final bool large;

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
                style: Type.sans(
                  large ? 14.5 : (roomy ? 14 : 13.5),
                  weight: FontWeight.w500,
                  color: t.ink,
                ),
              ),
              if (meta.isNotEmpty)
                Text(
                  meta,
                  maxLines: roomy ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sans(12, color: t.muted),
                ),
              ?below,
            ],
          ),
        ),
        for (final widget in trailing) ...[SizedBox(width: gap), widget],
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
