import 'package:flutter/material.dart';

import '../../core/activity.dart';
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
            'What the agent\'s code made in $name, newest first. A file that goes soon is '
            'deleted then unless you keep it.',
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
          FieldCard([
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(summary, style: Type.sans(12, color: t.muted)),
            ),
            if (list != null)
              for (final file in list.files)
                _FileRow(
                  file,
                  key: ValueKey(file.id),
                  now: now,
                  working: created.working.contains(file.id),
                  deleting: _deleting == file.id,
                  onDelete: () => setState(() => _deleting = file.id),
                  onCancel: () => setState(() => _deleting = null),
                  onConfirm: () {
                    setState(() => _deleting = null);
                    created.remove(file);
                  },
                ),
          ]),
          if (list?.truncated ?? false) ...[
            const SizedBox(height: 10),
            const HelpText('Only the newest files are listed.'),
          ],
          const SizedBox(height: 14),
          Text(
            'Deep research reports are in Documents, and files AnythingLLM\'s own tools make '
            'are not kept here.',
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
    final text = list.limit > 0
        ? '$used of ${sizeText(list.limit)} used'
        : used;
    return Semantics(
      label: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: t.line2)),
                  FractionallySizedBox(
                    widthFactor: list.fraction,
                    child: ColoredBox(
                      color: list.nearFull ? t.warnfg : t.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            list.nearFull ? '$text. Nearly full.' : text,
            style: Type.sans(12, color: list.nearFull ? t.warnfg : t.muted),
          ),
        ],
      ),
    );
  }
}

/// One file: its type, name, size and age, its mark when it has one, and what can be done with
/// it, under the name so the row fits any width. Delete asks once more.
class _FileRow extends StatelessWidget {
  const _FileRow(
    this.file, {
    super.key,
    required this.now,
    required this.working,
    required this.deleting,
    required this.onDelete,
    required this.onCancel,
    required this.onConfirm,
  });

  final CreatedFile file;
  final DateTime now;

  /// Whether the file is being kept or deleted.
  final bool working;
  final bool deleting;
  final VoidCallback onDelete;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final created = scope.created;
    final t = Tokens.of(context);
    final mark = createdMark(file, now);
    Widget action(String label, VoidCallback onTap) => TextAction.plain(
      label,
      onTap,
      semanticLabel: '$label ${file.name}',
      height: 32,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TypeTile.label(sourceExt(file.name)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sans(14, weight: FontWeight.w500, color: t.ink),
                ),
                Text(
                  [
                    if (file.dir.isNotEmpty) file.dir,
                    sizeText(file.size),
                    agoText(file.modified, now),
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sans(12, color: t.muted),
                ),
                if (mark != null) ...[
                  const SizedBox(height: 4),
                  AppBadge(
                    mark,
                    kind: file.area == CreatedArea.work
                        ? BadgeKind.warn
                        : BadgeKind.accent,
                  ),
                ],
                const SizedBox(height: 2),
                if (working)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: HelpText('Working…', status: true),
                  )
                else
                  Wrap(
                    spacing: 16,
                    children: [
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
                      if (file.area == CreatedArea.work)
                        action('Keep', () => created.keep(file)),
                      action('Delete', onDelete),
                    ],
                  ),
                if (deleting) ...[
                  const SizedBox(height: 8),
                  ConfirmBox(
                    text:
                        'Delete ${file.name} from the workspace? It cannot be got back.',
                    onCancel: onCancel,
                    onConfirm: onConfirm,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
