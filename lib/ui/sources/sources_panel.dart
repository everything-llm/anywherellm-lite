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
    final t = Tokens.of(context);
    return SidePanel(
      title: 'Documents',
      about: 'Answers draw on the ones switched on.',
      onClose: scope.shell.closeSources,
      child: ListenableBuilder(
        listenable: scope.sources,
        builder: (context, _) {
          final sources = scope.sources;
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
                    TestQuestion(
                      key: ValueKey(('test', scope.chat.activeSlug)),
                    ),
                    if (sources.sending case final name?) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Adding $name…',
                        style: Type.sans(12.5, color: t.muted),
                      ),
                    ],
                    for (final problem in sources.problems) ...[
                      const SizedBox(height: 10),
                      AlertBox(
                        AlertKind.bad,
                        problem.title,
                        text: problem.text,
                      ),
                    ],
                    if (sources.removed case final file?) ...[
                      const SizedBox(height: 10),
                      UndoBar(
                        'Removed ${file.title}',
                        onUndo: scope.sources.undo,
                      ),
                    ],
                    const SizedBox(height: 14),
                  ],
                ),
              ),
              if (sources.files.isEmpty)
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
                  itemCount: sources.files.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) => Rise(
                    key: ValueKey(sources.files[i].path),
                    child: _FileRow(
                      sources.files[i],
                      flashed: sources.flashed == sources.files[i].path,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow(this.file, {required this.flashed});

  final SourceFile file;
  final bool flashed;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    // A citation's flash fills the row and rings it in the accent; the ring is always there,
    // clear, so the flash moves nothing.
    return AnimatedContainer(
      duration: motion(context, const Duration(milliseconds: 300)),
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      decoration: BoxDecoration(
        color: flashed ? t.accentbg : Colors.transparent,
        border: Border.all(color: flashed ? t.accent : Colors.transparent),
        borderRadius: BorderRadius.circular(Sizes.control),
      ),
      child: SourceRow(
        file,
        meta: file.meta,
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
            box: 32,
            size: IconSize.xs,
            dangerHover: true,
            onPressed: () => scope.sources.remove(file),
          ),
        ],
      ),
    );
  }
}

/// A document's row: its [TypeTile], its title with [meta] and anything [below] under it, then
/// each of [trailing], such as its switch. [roomy] is how the Files pane draws it: a larger
/// title, wider gaps, and [meta] on up to two lines.
class SourceRow extends StatelessWidget {
  const SourceRow(
    this.file, {
    super.key,
    required this.meta,
    required this.trailing,
    this.below,
    this.roomy = false,
  });

  final SourceFile file;
  final String meta;
  final List<Widget> trailing;
  final Widget? below;
  final bool roomy;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final gap = roomy ? 12.0 : 10.0;
    return Row(
      children: [
        TypeTile(file),
        SizedBox(width: gap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                file.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.sans(
                  roomy ? 14 : 13.5,
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
  const TypeTile(this.file, {super.key});

  final SourceFile file;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Opacity(
      opacity: file.on ? 1 : 0.5,
      child: Container(
        width: 32,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.accentbg,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          file.tile,
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
