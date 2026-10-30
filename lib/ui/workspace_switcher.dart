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
import 'widgets/buttons.dart';
import 'widgets/fields.dart';
import 'widgets/phone_page.dart';
import 'widgets/tappable.dart';
import 'widgets/scroll_fades.dart';
import 'widgets/sheet.dart';

/// The shelf's title: the open workspace's name at [size] and a chevron, which open the
/// Workspaces sheet. Its documents are heard, not shown.
class WorkspaceSwitcher extends StatelessWidget {
  const WorkspaceSwitcher({super.key, this.size = 26});

  /// The name's size: 26 in the shelf, smaller in the sidebar.
  final double size;

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
        return Tappable(
          label: elsewhere ? '$name, an answer is ready in another' : name,
          expanded: shell.menuOpen,
          radius: BorderRadius.circular(Sizes.small),
          onTap: () => shell.togglePopup(Popup.workspaces),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              spacing: 6,
              children: [
                Flexible(
                  child: TitleRoom(
                    child: Semantics(
                      header: true,
                      child: Text(
                        active?.name ?? 'No workspace yet',
                        style: Type.display(
                          size,
                          letterSpacing: -0.3,
                          color: active == null ? t.muted : t.ink,
                        ),
                      ),
                    ),
                  ),
                ),
                AppIcon('down', color: t.muted),
                if (elsewhere) const ReadyMark(),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The Workspaces sheet: the workspaces in one card, each with how many documents it has, to
/// open one or press and hold to drag it to another place, and New workspace in another. Its
/// header's [ReorderButton] puts them in order with buttons instead. The rest is in the
/// workspace's settings.
class WorkspaceMenu extends StatelessWidget {
  const WorkspaceMenu({super.key, required this.onCreate});

  final VoidCallback onCreate;

  // The shell builds it for the popup alone, so it listens itself to the workspaces, their
  // counts and the order a drag saves.
  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.chat, scope.prefs]),
      builder: _build,
    );
  }

  Widget _build(BuildContext context, Widget? _) {
    final scope = AppScope.of(context);
    final ordered = scope.chat.orderedWorkspaces;
    final list = ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 400),
      child: _OrderList(ordered, row: (w, _) => _WorkspaceItem(w)),
    );
    return Semantics(
      container: true,
      label: 'Workspaces',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          if (ordered.isNotEmpty) FieldCard([list]),
          FieldCard([
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

/// The Workspaces sheet's Reorder, in its header, which opens Reorder workspaces in the sheet's
/// place while there are two workspaces or more to put in order.
class ReorderButton extends StatelessWidget {
  const ReorderButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: scope.chat,
      builder: (context, _) => scope.chat.workspaces.length < 2
          ? const SizedBox.shrink()
          // A word on no fill, sized to itself, since the title takes the rest of the line.
          : Tappable(
              touchTarget: true,
              label: 'Reorder',
              radius: BorderRadius.circular(Sizes.small),
              onTap: () => scope.shell.togglePopup(Popup.reorderWorkspaces),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    widthFactor: 1,
                    child: Text('Reorder', style: Type.label(t.accent)),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Reorder workspaces, in the Workspaces sheet's place: how to move them, then the workspaces in
/// the order [Prefs.workspaceOrder] gives, each with Move up and Move down, off at the ends of
/// the list, and dragged after a press and hold as in the Workspaces sheet; then Done, under a
/// rule, which gives the Workspaces sheet back. Each move is saved as it is made.
class WorkspaceOrder extends StatelessWidget {
  const WorkspaceOrder({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: HelpText(
                    'Move a workspace up or down. You can also press and hold a row, then '
                    'drag it.',
                  ),
                ),
                // The list scrolls in what is left of the sheet.
                Flexible(
                  child: ListenableBuilder(
                    listenable: Listenable.merge([scope.chat, scope.prefs]),
                    builder: (context, _) {
                      final ordered = scope.chat.orderedWorkspaces;
                      // A card as a [FieldCard] draws it, as tall as its rows.
                      return Semantics(
                        container: true,
                        label: 'Workspaces in order',
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: cardDecoration(
                            t,
                            inSheet: SheetFrame.holds(context),
                          ),
                          child: _OrderList(
                            ordered,
                            row: (w, i) => _OrderRow(
                              w,
                              up: i > 0 ? () => _move(scope, i, -1) : null,
                              down: i < ordered.length - 1
                                  ? () => _move(scope, i, 1)
                                  : null,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.line)),
          ),
          child: ActionRow(even: true, [
            AppButton(
              'Done',
              primary: true,
              onPressed: () => scope.shell.togglePopup(Popup.workspaces),
            ),
          ]),
        ),
      ],
    );
  }

  /// Moves the workspace at [i] in the order [by] places, one up or down.
  static void _move(AppScope scope, int i, int by) {
    final slugs = [for (final w in scope.chat.orderedWorkspaces) w.slug];
    slugs.insert(i + by, slugs.removeAt(i));
    scope.prefs.setWorkspaceOrder(slugs);
  }
}

/// [ordered] in a list a press and hold drags a row of, each row built by [row] under a rule
/// after the first; a drag saves the order. It scrolls past the room it is given.
class _OrderList extends StatelessWidget {
  const _OrderList(this.ordered, {required this.row});

  final List<Workspace> ordered;
  final Widget Function(Workspace workspace, int index) row;

  @override
  Widget build(BuildContext context) {
    final prefs = AppScope.of(context).prefs;
    // A card in a sheet is the page's own ground, which the fades blend into.
    return ScrollFades(
      child: ReorderableListView.builder(
        shrinkWrap: true,
        // The row starts a drag, not a handle beside it.
        buildDefaultDragHandles: false,
        itemCount: ordered.length,
        onReorderItem: (from, to) {
          final slugs = [for (final w in ordered) w.slug];
          slugs.insert(to, slugs.removeAt(from));
          prefs.setWorkspaceOrder(slugs);
        },
        // The dragged row is drawn in the app's overlay, outside AppScope, so it is shown as
        // a name alone.
        proxyDecorator: (child, i, animation) => _DragGhost(ordered[i].name),
        // A press and hold starts the drag, since a touch would otherwise scroll.
        itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
          key: ValueKey(ordered[i].slug),
          index: i,
          child: Ruled(ruled: i > 0, child: row(ordered[i], i)),
        ),
      ),
    );
  }
}

/// A workspace in the sheet, with its document count: tapped, it opens; pressed and held, it
/// moves.
class _WorkspaceItem extends StatelessWidget {
  const _WorkspaceItem(this.workspace);

  final Workspace workspace;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final t = Tokens.of(context);
    final active = chat.activeSlug == workspace.slug;
    final ready = !active && chat.readyIn(workspace.slug);
    final count = chat.docCounts[workspace.slug];
    return CardRow(
      workspace.name,
      heard: ready ? '${workspace.name}, answer ready' : null,
      checked: active,
      onTap: () {
        scope.shell.closePopup(Popup.workspaces);
        if (!active) chat.select(workspace.slug);
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          if (ready) const ReadyMark(),
          if (count != null)
            Text(
              plural(count, 'document', 'documents'),
              style: Type.note(t.ink),
            ),
        ],
      ),
    );
  }
}

/// A workspace in Reorder workspaces: its name over its document count, then Move up and Move
/// down, each off where [up] or [down] is null.
class _OrderRow extends StatelessWidget {
  const _OrderRow(this.workspace, {required this.up, required this.down});

  final Workspace workspace;
  final VoidCallback? up;
  final VoidCallback? down;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final count = AppScope.of(context).chat.docCounts[workspace.slug];
    final name = workspace.name;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Sizes.cardRow),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FieldCard.inset, 8, 12, 8),
        child: Row(
          spacing: 12,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Type.body(t.ink)),
                  if (count != null)
                    Text(
                      plural(count, 'document', 'documents'),
                      style: Type.note(t.ink),
                    ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                IconBtn(
                  'arrowUp',
                  tooltip: 'Move $name up',
                  box: 48,
                  filled: true,
                  size: IconSize.small,
                  onPressed: up,
                ),
                IconBtn(
                  'arrowDown',
                  tooltip: 'Move $name down',
                  box: 48,
                  filled: true,
                  size: IconSize.small,
                  onPressed: down,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A workspace as it looks while it is dragged.
class _DragGhost extends StatelessWidget {
  const _DragGhost(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.tile,
        borderRadius: BorderRadius.circular(Sizes.small),
        boxShadow: t.raisedShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Text(name, style: Type.body(t.ink, weight: FontWeight.w600)),
      ),
    );
  }
}
