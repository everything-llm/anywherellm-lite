import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/copy.dart';
import '../core/server_models.dart';
import 'app_scope.dart';
import 'icons.dart';
import 'layout.dart';
import 'state/chat_controller.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/basics.dart';
import 'widgets/confirm_box.dart';
import 'widgets/inline_input.dart';
import 'widgets/menu.dart';
import 'widgets/sheet.dart';
import 'widgets/tappable.dart';

/// Whether Ctrl+1 to Ctrl+9 are shown beside the workspaces: on a desktop, where there is a
/// keyboard and no browser takes those keys first.
bool showsWorkspaceKeys(BuildContext context) =>
    !kIsWeb &&
    const {
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }.contains(Theme.of(context).platform);

/// What the sidebar asks about a workspace: a new name for the open one, in the switcher's
/// place; whether to delete it, or a new workspace's name, in place of the chats.
enum Asking { nothing, rename, delete, create }

/// The question the sidebar asks about a workspace, and its answers. It drops a question once
/// its workspace is no longer the open one, or a delete once it starts answering, when the
/// answer could no longer do what it asks.
class WorkspaceAsk extends ChangeNotifier {
  WorkspaceAsk(this._chat, this._shell) {
    _chat.addListener(_chatChanged);
  }

  final ChatController _chat;
  final ShellController _shell;

  /// The name typed, for a rename or a new workspace.
  final name = TextEditingController();

  Asking _asking = Asking.nothing;
  Asking get asking => _asking;

  /// The workspace a question is about.
  String? _about;

  @override
  void dispose() {
    _chat.removeListener(_chatChanged);
    name.dispose();
    super.dispose();
  }

  void _chatChanged() {
    if (_asking == Asking.nothing || _asking == Asking.create) return;
    final slug = _about;
    if (_chat.activeSlug == slug &&
        !(_asking == Asking.delete && _chat.answeringIn(slug!))) {
      return;
    }
    reset();
  }

  void ask(Asking what) {
    _shell.closePopup(Popup.workspaces);
    final active = _chat.active;
    _asking = what;
    _about = active?.slug;
    final text = what == Asking.rename ? active?.name ?? '' : '';
    name
      ..text = text
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    notifyListeners();
  }

  void reset() {
    if (_asking == Asking.nothing) return;
    _asking = Asking.nothing;
    _about = null;
    name.clear();
    notifyListeners();
  }

  Future<void> rename() async {
    final typed = name.text.trim();
    final slug = _about;
    final was = _chat.active?.name;
    reset();
    if (slug != null && typed.isNotEmpty && typed != was) {
      await _chat.renameWorkspace(slug, typed);
    }
  }

  Future<void> create() async {
    final typed = name.text.trim();
    reset();
    if (typed.isEmpty) return;
    await _chat.createWorkspace(typed);
    _shell.closeSide();
  }

  void delete() {
    final slug = _about;
    reset();
    if (slug != null) _chat.deleteWorkspace(slug);
  }
}

/// [ask]'s delete question or new workspace's name, which take the chats' place under the
/// switcher, scrolling where the screen is short.
class WorkspaceQuestion extends StatelessWidget {
  const WorkspaceQuestion(this.ask, {super.key});

  final WorkspaceAsk ask;

  @override
  Widget build(BuildContext context) {
    final chat = AppScope.of(context).chat;
    return SingleChildScrollView(
      child: ask.asking == Asking.delete
          ? ConfirmBox(
              text:
                  'Delete ${chat.active?.name} and its ${plural(chat.threadsOf(chat.activeSlug ?? '').length, 'chat', 'chats')}? Its documents stay in the library.',
              onCancel: ask.reset,
              onConfirm: ask.delete,
            )
          : InlineInput(
              controller: ask.name,
              label: 'New workspace name',
              hint: 'Workspace name',
              height: 36,
              onSubmit: ask.create,
              onCancel: ask.reset,
            ),
    );
  }
}

/// The open workspace at the top of the sidebar, and the menu it opens: every workspace, to
/// switch to or drag into another place, then Files and settings (Chats while Files shows),
/// the open workspace's Rename and Delete, and New workspace. A rename is asked in its place.
class WorkspaceSwitcher extends StatefulWidget {
  const WorkspaceSwitcher(this.ask, {super.key});

  final WorkspaceAsk ask;

  @override
  State<WorkspaceSwitcher> createState() => _WorkspaceSwitcherState();
}

class _WorkspaceSwitcherState extends State<WorkspaceSwitcher> {
  late final ChatController _chat;
  late final ShellController _shell;

  @override
  void initState() {
    super.initState();
    final scope = AppScope.of(context);
    _chat = scope.chat;
    _shell = scope.shell;
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final ask = widget.ask;
    return ListenableBuilder(
      listenable: Listenable.merge([_chat, scope.prefs, _shell.popup, ask]),
      builder: (context, _) => ask.asking == Asking.rename
          ? InlineInput(
              controller: ask.name,
              label: 'Workspace name',
              height: 44,
              maxLength: 80,
              onSubmit: ask.rename,
              onCancel: ask.reset,
              commitOnBlur: true,
            )
          : ScreenClass.ofContext(context).isPhone
          // A phone's menu is a sheet over the window.
          ? PopupSheet(
              open: _shell.menuOpen,
              onClose: () => _shell.closePopup(Popup.workspaces),
              title: 'Workspaces',
              sheet: (context) => SingleChildScrollView(
                child: _WorkspaceMenu(
                  sheet: true,
                  onRename: () => ask.ask(Asking.rename),
                  onDelete: () => ask.ask(Asking.delete),
                  onCreate: () => ask.ask(Asking.create),
                ),
              ),
              child: _button(context),
            )
          : PopupAnchor(
              open: _shell.menuOpen,
              onClose: () => _shell.closePopup(Popup.workspaces),
              // As wide as the switcher.
              menu: (context) => SizedBox(
                width: Sizes.sidebar - 24,
                child: _WorkspaceMenu(
                  onRename: () => ask.ask(Asking.rename),
                  onDelete: () => ask.ask(Asking.delete),
                  onCreate: () => ask.ask(Asking.create),
                ),
              ),
              child: _button(context),
            ),
    );
  }

  Widget _button(BuildContext context) {
    final t = Tokens.of(context);
    final active = _chat.active;
    final open = _shell.menuOpen;
    final count = active == null ? null : _chat.docCounts[active.slug];
    // Another workspace has an answer ready.
    final elsewhere = _chat.workspaces.any(
      (w) => w.slug != active?.slug && _chat.readyIn(w.slug),
    );
    final name = active == null ? 'Workspaces' : 'Workspaces: ${active.name}';
    // A phone's is 48 tall, its name at 15 over a sheet that rises below, as the design canvas
    // draws it.
    final phone = ScreenClass.ofContext(context).isPhone;
    return Tappable(
      label: elsewhere ? '$name, an answer is ready in another' : name,
      tooltip: 'Switch workspace',
      expanded: open,
      onTap: () => _shell.togglePopup(Popup.workspaces),
      radius: BorderRadius.circular(Sizes.controlOf(context)),
      color: open ? t.hover : t.panel,
      side: BorderSide(color: t.line),
      child: SizedBox(
        height: Sizes.fieldOf(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  active?.name ?? 'No workspace yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sans(
                    phone ? 15 : 14.5,
                    weight: FontWeight.w600,
                    color: active == null ? t.muted : t.ink,
                  ),
                ),
              ),
              if (count != null && count > 0) ...[
                const SizedBox(width: 8),
                Text(
                  plural(count, 'doc', 'docs'),
                  style: Type.sans(12, color: t.muted),
                ),
              ],
              if (elsewhere) const ReadyDot(),
              const SizedBox(width: 8),
              AppIcon(
                phone ? 'down' : 'unfold',
                size: IconSize.xs,
                color: t.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The workspaces, to open one or drag it to another place, then Files and settings, Rename,
/// Delete and New workspace. In a phone's [sheet] each workspace says how many documents it
/// has, and Files and settings is named for the workspace's pages.
class _WorkspaceMenu extends StatelessWidget {
  const _WorkspaceMenu({
    required this.onRename,
    required this.onDelete,
    required this.onCreate,
    this.sheet = false,
  });

  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onCreate;
  final bool sheet;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final shell = scope.shell;
    final ordered = scope.prefs.prefs.inOrder(chat.workspaces, (w) => w.slug);
    final active = chat.active;
    final keys = showsWorkspaceKeys(context);
    // A phone's sheet draws it plain, as its other rows are, as the design canvas does.
    final create = AppMenuItem(
      'New workspace',
      icon: sheet ? null : 'plus',
      accent: !sheet,
      onTap: onCreate,
    );
    final rename = active == null
        ? null
        : AppMenuItem('Rename workspace', onTap: onRename);
    final delete = active == null
        ? null
        : AppMenuItem(
            'Delete workspace…',
            danger: true,
            onTap: chat.answeringIn(active.slug) ? null : onDelete,
          );
    final items = <Widget>[
      if (ordered.isNotEmpty)
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: sheet ? 400 : 320),
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
            // The dragged row is drawn in the app's overlay, outside AppScope, so it is
            // shown as a name alone.
            proxyDecorator: (child, i, animation) =>
                _DragGhost(ordered[i].name),
            itemBuilder: (context, i) => _WorkspaceItem(
              ordered[i],
              key: ValueKey(ordered[i].slug),
              index: i,
              shortcut: keys && i < 9 ? 'Ctrl ${i + 1}' : null,
              sheet: sheet,
            ),
          ),
        ),
      if (ordered.isNotEmpty) const MenuDivider(),
      AppMenuItem(
        shell.pane == Pane.files
            ? 'Chats'
            : sheet
            ? 'Documents, instructions and settings'
            : 'Files and settings',
        onTap: () {
          if (sheet) {
            shell.closePopup(Popup.workspaces);
            shell.closeSide();
          }
          shell.showPane(shell.pane == Pane.files ? Pane.chats : Pane.files);
        },
      ),
      // A phone's sheet puts New workspace before Delete, which comes last.
      ...sheet
          ? [?rename, create, ?delete]
          : [?rename, ?delete, const MenuDivider(), create],
    ];
    if (sheet) {
      return Semantics(
        container: true,
        label: 'Workspaces',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: items,
        ),
      );
    }
    return AppMenu(label: 'Workspaces', children: items);
  }
}

/// A workspace in the menu: tapped, it opens; dragged, it moves.
class _WorkspaceItem extends StatelessWidget {
  const _WorkspaceItem(
    this.workspace, {
    super.key,
    required this.index,
    this.shortcut,
    this.sheet = false,
  });

  /// In a phone's sheet: taller, with the workspace's document count.
  final bool sheet;

  final Workspace workspace;

  /// Where the row sits in the menu, for dragging it to another place.
  final int index;

  /// The keys that open it, such as Ctrl 1, or null.
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final t = Tokens.of(context);
    final active = chat.activeSlug == workspace.slug;
    final ready = !active && chat.readyIn(workspace.slug);
    final count = sheet ? chat.docCounts[workspace.slug] : null;
    return _Draggable(
      index: index,
      child: Tappable(
        label: ready ? '${workspace.name}, answer ready' : workspace.name,
        selected: active,
        onTap: () {
          scope.shell.closePopup(Popup.workspaces);
          if (!active) chat.select(workspace.slug);
        },
        radius: BorderRadius.circular(8),
        color: active ? t.sel : null,
        child: SizedBox(
          height: sheet ? 48 : 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  child: active
                      ? AppIcon('check', size: IconSize.xs, color: t.accent)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    workspace.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sans(
                      sheet ? 15.5 : 14,
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
                    style: Type.sans(12.5, color: t.muted),
                  ),
                ],
                if (shortcut != null)
                  Text(shortcut!, style: Type.sans(12, color: t.muted)),
              ],
            ),
          ),
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
    return Material(
      color: t.panel,
      elevation: 6,
      shadowColor: t.shadow,
      borderRadius: BorderRadius.circular(8),
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

/// Starts dragging its [child] to another place in the list: at once with a mouse, after a
/// press and hold on a touch screen, which would otherwise scroll.
class _Draggable extends StatelessWidget {
  const _Draggable({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => switch (Theme.of(context).platform) {
    TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia =>
      ReorderableDelayedDragStartListener(index: index, child: child),
    _ => ReorderableDragStartListener(index: index, child: child),
  };
}
