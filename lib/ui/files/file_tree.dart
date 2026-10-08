import 'package:flutter/material.dart';

import '../../core/files.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import 'essentials.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/segmented.dart';
import '../widgets/tappable.dart';

/// The server's data as a folder tree, in the sidebar while Files is on screen, or the
/// Essentials view's sections, as the switch under the heading says.
class FileTree extends StatefulWidget {
  const FileTree({super.key});

  @override
  State<FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends State<FileTree> {
  @override
  void initState() {
    super.initState();
    // Loading notifies, which must wait until the frame that builds the tree is done.
    final files = AppScope.of(context).files;
    WidgetsBinding.instance.addPostFrameCallback((_) => files.ensureLoaded());
  }

  @override
  Widget build(BuildContext context) {
    final files = AppScope.of(context).files;
    return ListenableBuilder(
      listenable: files,
      builder: (context, _) {
        final rows = <(FileNode, int)>[];
        void walk(FileNode node, int depth) {
          for (final child in node.children) {
            rows.add((child, depth));
            if (child.kind.isFolder && files.expanded.contains(child.path)) {
              walk(child, depth + 1);
            }
          }
        }

        walk(files.tree, 0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SidebarSection(
              'Files',
              action: IconBtn(
                'refresh',
                tooltip: 'Read again',
                box: 24,
                size: IconSize.xs,
                onPressed: files.loading ? null : files.load,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Segmented<bool>(
                options: const [(true, 'Essentials'), (false, 'All files')],
                value: files.essentials,
                onChanged: files.showEssentials,
              ),
            ),
            if (files.essentials)
              const Expanded(child: EssentialsList())
            else
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final (node, depth) = rows[i];
                    return _Row(
                      node,
                      depth: depth,
                      open: files.expanded.contains(node.path),
                      selected: files.selected == node.path,
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(
    this.node, {
    required this.depth,
    required this.open,
    required this.selected,
  });

  final FileNode node;
  final int depth;
  final bool open;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final files = scope.files;
    final t = Tokens.of(context);
    final folder = node.kind.isFolder;
    return Tappable(
      label: node.name,
      selected: selected,
      expanded: folder ? open : null,
      onTap: () {
        if (folder && (!open || selected)) files.toggle(node.path);
        files.select(node.path);
        if (!folder) scope.shell.closeSide();
      },
      radius: BorderRadius.circular(8),
      color: selected ? t.sel : null,
      child: Padding(
        padding: EdgeInsets.fromLTRB(6.0 + depth * 14, 6, 8, 6),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: folder
                  ? AnimatedRotation(
                      turns: open ? 0.25 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: AppIcon(
                        'chevron',
                        size: IconSize.xs,
                        color: t.muted,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 4),
            AppIcon(
              switch (node.kind) {
                NodeKind.locked => 'lock',
                NodeKind.chatLog => 'chat',
                _ when folder => 'folder',
                _ => 'doc',
              },
              size: IconSize.xs,
              color: t.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.sans(
                  13.5,
                  weight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: node.kind == NodeKind.locked ? t.muted : t.ink,
                ),
              ),
            ),
            if (node.pinned) ...[
              const SizedBox(width: 6),
              const AppBadge('pinned', kind: BadgeKind.accent),
            ],
            if (badgeText(node.badge) case final text?) ...[
              const SizedBox(width: 6),
              AppBadge(text, kind: BadgeKind.warn),
            ],
          ],
        ),
      ),
    );
  }
}

/// The words on a node's badge, or null for a node without one.
String? badgeText(NodeBadge badge) => switch (badge) {
  NodeBadge.none => null,
  NodeBadge.readOnly => 'Read only',
  NodeBadge.locked => 'Locked',
};
