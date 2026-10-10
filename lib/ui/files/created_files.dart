import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/created.dart';
import '../../core/outputs.dart';
import '../../core/upload.dart';
import '../app_scope.dart';
import '../links.dart';
import '../settings/rows.dart';
import '../sources/sources_panel.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/confirm_box.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';
import 'essentials.dart';
import 'save_file.dart';

/// The files the agent's code made in the open workspace, newest first, under how much of the
/// workspace's room is used. Each has Download; a working file has Keep, since it goes a week
/// after its chat last used the sandbox; a page on the web has Open page. A row is marked only
/// when it differs from a kept file.
class CreatedFiles extends StatefulWidget {
  const CreatedFiles({super.key});

  @override
  State<CreatedFiles> createState() => _CreatedFilesState();
}

class _CreatedFilesState extends State<CreatedFiles> {
  /// The narrowest list whose rows have their mark and actions beside the name.
  static const _wideFrom = 580.0;

  /// The file whose Delete is asking once more.
  String? _deleting;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final created = scope.created;
    final t = Tokens.of(context);
    created.want();
    return ListenableBuilder(
      listenable: created,
      builder: (context, _) {
        final list = created.list;
        final name = scope.chat.active?.name ?? 'this workspace';
        if (created.unavailable) {
          return EssentialsPage([
            Text(
              'Files the agent makes while answering in $name appear under the answer that '
              'made them, where each one can be saved.',
              style: Type.sans(14, color: t.ink2, height: 1.5),
            ),
            const SizedBox(height: 12),
            Text(
              'This server has no list of them all, so they are not gathered here.',
              style: Type.sans(12.5, color: t.muted, height: 1.45),
            ),
          ]);
        }
        final now = DateTime.now();
        final summary = switch (list) {
          null => created.loading ? 'Loading…' : 'Not read yet.',
          CreatedList(files: []) => 'No files yet.',
          _ => plural(list.files.length, 'file', 'files'),
        };
        return EssentialsPage([
          Text(
            'Files the agent made or downloaded in $name, newest first. A working file goes 7 '
            'days after its chat last used it, unless you keep it.',
            style: Type.sans(14, color: t.ink2, height: 1.5),
          ),
          const SizedBox(height: 14),
          if (list != null) ...[_Meter(list), const SizedBox(height: 10)],
          Align(
            alignment: Alignment.centerLeft,
            child: TextAction.plain(
              created.loading ? 'Reading…' : 'Refresh',
              () {
                if (!created.loading) created.read();
              },
              semanticLabel: 'Refresh created files',
              height: 32,
            ),
          ),
          if (created.problem case final problem?) ...[
            const SizedBox(height: 10),
            AlertBox(AlertKind.bad, problem.title, text: problem.text),
          ],
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= _wideFrom;
              return FieldCard([
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(summary, style: Type.sans(12, color: t.muted)),
                ),
                if (list != null)
                  for (final file in list.files)
                    _FileRow(
                      file,
                      key: ValueKey(file.id),
                      now: now,
                      wide: wide,
                      working: created.working.contains(file.id),
                      deleting: _deleting == file.id,
                      onDelete: () => setState(() => _deleting = file.id),
                      onCancel: () => setState(() => _deleting = null),
                      onConfirm: () {
                        setState(() => _deleting = null);
                        created.remove(file);
                      },
                    ),
              ]);
            },
          ),
          if (list?.truncated ?? false) ...[
            const SizedBox(height: 10),
            const HelpText('Only the newest files are listed.'),
          ],
          const SizedBox(height: 14),
          Text(
            'Not listed here: deep research reports, which are added to Documents, and files '
            'written with the File System Access skill, which sit in one folder for the whole '
            'server.',
            style: Type.sans(12.5, color: t.muted, height: 1.45),
          ),
        ]);
      },
    );
  }
}

/// How much of the workspace's room is used, on a bar, in the warning colour once past the size
/// the host warns at.
class _Meter extends StatelessWidget {
  const _Meter(this.list);

  final CreatedList list;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final used = sizeText(list.used);
    final text = list.limit > 0 ? '$used of ${sizeText(list.limit)}' : used;
    final full = list.nearFull ? '. Nearly full.' : '';
    final color = list.nearFull ? t.warnfg : t.accent;
    return Semantics(
      container: true,
      label: '$text used$full',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  child: Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: t.line2)),
                      FractionallySizedBox(
                        widthFactor: list.fraction,
                        child: ColoredBox(color: color),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$text$full',
              style: Type.sans(12.5, color: list.nearFull ? t.warnfg : t.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// One file: its type, name and [createdMeta], its mark when it has one, and what can be done
/// with it, beside the name when [wide] and under it otherwise. Delete asks once more.
class _FileRow extends StatelessWidget {
  const _FileRow(
    this.file, {
    super.key,
    required this.now,
    required this.wide,
    required this.working,
    required this.deleting,
    required this.onDelete,
    required this.onCancel,
    required this.onConfirm,
  });

  final CreatedFile file;
  final DateTime now;
  final bool wide;

  /// Whether the file is being kept or deleted.
  final bool working;
  final bool deleting;
  final VoidCallback onDelete;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final created = AppScope.of(context).created;
    final mark = createdMark(file, now);
    Widget action(String label, VoidCallback onTap) => TextAction.plain(
      label,
      onTap,
      semanticLabel: '$label ${file.name}',
      height: 32,
    );
    final badge = mark == null
        ? null
        : AppBadge(
            mark,
            kind: file.area == CreatedArea.work
                ? BadgeKind.warn
                : BadgeKind.accent,
          );
    final actions = working
        ? const HelpText('Working…', status: true)
        : Wrap(
            spacing: 16,
            children: [
              if (file.area == CreatedArea.work)
                action('Keep', () => created.keep(file)),
              action(
                'Download',
                () => saveFile(
                  context,
                  file.name,
                  () => created.bytes(file),
                  failTitle: 'Could not save ${file.name}',
                  report: created.report,
                ),
              ),
              if (file.isPage)
                action('Open page', () => openLink(context, file.url!)),
              action('Delete', onDelete),
            ],
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SourceRow.label(
            tile: TypeTile.label(sourceExt(file.name)),
            title: file.name,
            meta: createdMeta(file, now),
            roomy: true,
            below: wide
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (badge != null) ...[const SizedBox(height: 4), badge],
                      const SizedBox(height: 2),
                      actions,
                    ],
                  ),
            trailing: [
              if (wide) ...[?badge, actions],
            ],
          ),
          if (deleting) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 44, right: 4),
              child: ConfirmBox(
                text:
                    'Delete ${file.name} from the workspace? It cannot be got back.',
                onCancel: onCancel,
                onConfirm: onConfirm,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
