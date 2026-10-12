import 'package:flutter/material.dart';

import '../core/copy.dart';
import '../core/server_models.dart';
import 'app_scope.dart';
import 'icons.dart';
import 'layout.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'type.dart';
import 'settings/rows.dart';
import 'widgets/basics.dart';
import 'widgets/sheet.dart';
import 'widgets/tappable.dart';

/// The Chats tab's title: the open workspace's name at 26 and a chevron, which open the
/// Workspaces sheet. Its documents are heard, not shown.
class WorkspaceSwitcher extends StatelessWidget {
  const WorkspaceSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final shell = scope.shell;
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([chat, scope.prefs, shell.popup]),
      builder: (context, _) {
        final active = chat.active;
        final count = active == null ? null : chat.docCounts[active.slug];
        final elsewhere = chat.workspaces.any(
          (w) => w.slug != active?.slug && chat.readyIn(w.slug),
        );
        final docs = count != null && count > 0
            ? ', ${plural(count, 'doc', 'docs')}'
            : '';
        final name = active == null
            ? 'Workspaces'
            : 'Workspace: ${active.name}$docs. Switch workspace';
        return PopupSheet(
          open: shell.menuOpen,
          onClose: () => shell.closePopup(Popup.workspaces),
          title: 'Workspaces',
          sheet: (context) => SingleChildScrollView(
            child: _WorkspaceMenu(
              onCreate: () => shell.togglePopup(WorkspaceSheet.create),
            ),
          ),
          child: Tappable(
            label: elsewhere ? '$name, an answer is ready in another' : name,
            expanded: shell.menuOpen,
            radius: BorderRadius.circular(Sizes.control),
            onTap: () => shell.togglePopup(Popup.workspaces),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                spacing: 6,
                children: [
                  Flexible(
                    child: Semantics(
                      header: true,
                      child: Text(
                        active?.name ?? 'No workspace yet',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.sans(
                          26,
                          weight: FontWeight.w600,
                          letterSpacing: -0.3,
                          color: active == null ? t.muted : t.ink,
                        ),
                      ),
                    ),
                  ),
                  AppIcon('down', color: t.muted),
                  if (elsewhere) const ReadyDot(gap: false),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The Workspaces sheet: the workspaces in one card, each with how many documents it has, to
/// open one or press and hold to drag it to another place, and New workspace in another. The
/// rest is in the workspace's settings.
class _WorkspaceMenu extends StatelessWidget {
  const _WorkspaceMenu({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final ordered = scope.prefs.prefs.inOrder(
      scope.chat.workspaces,
      (w) => w.slug,
    );
    final list = ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 400),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        // The row starts a drag, not a handle beside it.
        buildDefaultDragHandles: false,
        itemCount: ordered.length,
        onReorderItem: (from, to) {
          final slugs = [for (final w in ordered) w.slug];
          slugs.insert(to, slugs.removeAt(from));
          scope.prefs.setWorkspaceOrder(slugs);
        },
        // The dragged row is drawn in the app's overlay, outside AppScope, so it is shown as
        // a name alone.
        proxyDecorator: (child, i, animation) => _DragGhost(ordered[i].name),
        itemBuilder: (context, i) => _WorkspaceItem(
          ordered[i],
          key: ValueKey(ordered[i].slug),
          index: i,
        ),
      ),
    );
    return Semantics(
      container: true,
      label: 'Workspaces',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          if (ordered.isNotEmpty) FieldCard(inSheet: true, [list]),
          FieldCard(inSheet: true, [
            CardRow(
              'New workspace',
              icon: 'plus',
              tone: RowTone.accent,
              strong: true,
              onTap: onCreate,
            ),
          ]),
        ],
      ),
    );
  }
}

/// A workspace in the sheet, with its document count: tapped, it opens; pressed and held, it
/// moves.
class _WorkspaceItem extends StatelessWidget {
  const _WorkspaceItem(this.workspace, {super.key, required this.index});

  final Workspace workspace;

  /// Where the row sits in the list, for dragging it to another place.
  final int index;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final t = Tokens.of(context);
    final active = chat.activeSlug == workspace.slug;
    final ready = !active && chat.readyIn(workspace.slug);
    final count = chat.docCounts[workspace.slug];
    // A press and hold starts the drag, since a touch would otherwise scroll.
    return ReorderableDelayedDragStartListener(
      index: index,
      child: _Ruled(
        ruled: index > 0,
        child: Tappable(
          label: ready ? '${workspace.name}, answer ready' : workspace.name,
          selected: active,
          onTap: () {
            scope.shell.closePopup(Popup.workspaces);
            if (!active) chat.select(workspace.slug);
          },
          child: SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: FieldCard.inset),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: active
                        ? AppIcon('check', size: IconSize.normal, color: t.ink)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      workspace.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.sans(
                        17,
                        weight: active ? FontWeight.w600 : FontWeight.w400,
                        color: t.ink,
                      ),
                    ),
                  ),
                  if (ready) const ReadyDot(),
                  if (count != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      plural(count, 'doc', 'docs'),
                      style: Type.sans(13, color: t.muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [child] under a hairline [FieldCard.inset] short of its sides when [ruled], as a row of a
/// grouped card under another is.
class _Ruled extends StatelessWidget {
  const _Ruled({required this.ruled, required this.child});

  final bool ruled;
  final Widget child;

  @override
  Widget build(BuildContext context) => !ruled
      ? child
      : CustomPaint(
          foregroundPainter: CardHairline(Tokens.of(context).line2),
          child: child,
        );
}

/// A workspace as it looks while it is dragged.
class _DragGhost extends StatelessWidget {
  const _DragGhost(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Material(
      color: t.panel,
      elevation: 6,
      shadowColor: t.shadow,
      borderRadius: BorderRadius.circular(Sizes.row),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Type.sans(14, weight: FontWeight.w600, color: t.ink),
        ),
      ),
    );
  }
}
