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
import '../widgets/drop_zone.dart';
import '../widgets/rise.dart';
import '../widgets/tappable.dart';
import 'add_source.dart';

/// The active workspace's files: add them, switch them on and off, remove them.
class SourcesPanel extends StatelessWidget {
  const SourcesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return Semantics(
      container: true,
      label: 'Sources',
      child: Container(
        width: Sizes.sources,
        decoration: BoxDecoration(
          color: t.panel2,
          border: Border(left: BorderSide(color: t.line)),
        ),
        padding: const EdgeInsets.all(16),
        child: ListenableBuilder(
          listenable: scope.sources,
          builder: (context, _) {
            final sources = scope.sources;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Sources',
                          style: Type.sans(
                            15,
                            weight: FontWeight.w600,
                            color: t.ink,
                          ),
                        ),
                      ),
                    ),
                    IconBtn(
                      'close',
                      tooltip: 'Close',
                      box: 28,
                      size: IconSize.xs,
                      onPressed: scope.shell.closeSources,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Only switched-on files are used to answer.',
                  style: Type.sans(13, color: t.muted),
                ),
                const SizedBox(height: 14),
                DropZone(onFiles: sources.upload, onProblem: sources.report),
                const SizedBox(height: 8),
                const AddSource(),
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
                  _UndoToast(file),
                ],
                const SizedBox(height: 14),
                Expanded(
                  child: sources.files.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            sources.loading ? 'Loading…' : 'No files yet.',
                            textAlign: TextAlign.center,
                            style: Type.sans(13.5, color: t.muted),
                          ),
                        )
                      : ListView.separated(
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
                ),
              ],
            );
          },
        ),
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
    return AnimatedContainer(
      duration: motion(context, const Duration(milliseconds: 300)),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: flashed ? t.accentbg : t.panel,
        borderRadius: BorderRadius.circular(Sizes.control),
        border: Border.all(color: flashed ? t.accent : t.line2),
      ),
      child: Row(
        children: [
          Opacity(
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
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Opacity(
              opacity: file.on ? 1 : 0.5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sans(
                      13.5,
                      weight: FontWeight.w500,
                      color: t.ink,
                    ),
                  ),
                  if (file.meta.isNotEmpty)
                    Text(file.meta, style: Type.sans(12, color: t.muted)),
                ],
              ),
            ),
          ),
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

class _UndoToast extends StatelessWidget {
  const _UndoToast(this.file);

  final SourceFile file;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(
          color: t.ink,
          borderRadius: BorderRadius.circular(Sizes.control),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Removed ${file.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.sans(13, color: t.bg),
              ),
            ),
            Tappable(
              label: 'Undo',
              onTap: scope.sources.undo,
              radius: BorderRadius.circular(6),
              hoverColor: t.bg.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Text(
                  'Undo',
                  style: Type.sans(13, weight: FontWeight.w600, color: t.bg),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
