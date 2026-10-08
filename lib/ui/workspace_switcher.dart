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
import 'widgets/confirm_box.dart';
import 'widgets/inline_input.dart';
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
    _shell.closeMenu();
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
                  'Delete ${chat.active?.name} and its ${plural(chat.threadsOf(ask._about ?? '').length, 'chat', 'chats')}? Its documents stay in the library.',
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
  final _menu = OverlayPortalController();
  final _link = LayerLink();

  /// The switcher and the menu tap as one: a tap on the switcher is not a tap outside the menu.
  final _group = Object();
  late final ChatController _chat;
  late final ShellController _shell;

  @override
  void initState() {
    super.initState();
    final scope = AppScope.of(context);
    _chat = scope.chat;
    _shell = scope.shell..addListener(_shellChanged);
    // Built anew in a drawer while the menu was open, as when the window narrows.
    if (_shell.menuOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _shellChanged());
    }
  }

  @override
  void dispose() {
    _shell.removeListener(_shellChanged);
    super.dispose();
  }

  void _shellChanged() {
    if (!mounted) return;
    if (_shell.menuOpen && !_menu.isShowing) _menu.show();
    if (!_shell.menuOpen && _menu.isShowing) _menu.hide();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final ask = widget.ask;
    return ListenableBuilder(
      listenable: Listenable.merge([_chat, scope.prefs, _shell, ask]),
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
          : TapRegion(
              groupId: _group,
              child: CompositedTransformTarget(
                link: _link,
                child: OverlayPortal(
                  controller: _menu,
                  overlayChildBuilder: _overlay,
                  child: _button(context),
                ),
              ),
            ),
    );
  }

  Widget _button(BuildContext context) {
    final t = Tokens.of(context);
    final active = _chat.active;
    final open = _shell.menuOpen;
    final count = active == null ? null : _chat.docCounts[active.slug];
    return Tappable(
      label: active == null ? 'Workspaces' : 'Workspaces: ${active.name}',
      tooltip: 'Switch workspace',
      expanded: open,
      onTap: _shell.toggleMenu,
      radius: BorderRadius.circular(Sizes.control),
      color: open ? t.hover : t.panel,
      side: BorderSide(color: t.line),
      child: SizedBox(
        height: 44,
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
                    14.5,
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
              const SizedBox(width: 8),
              AppIcon('unfold', size: IconSize.xs, color: t.muted),
            ],
          ),
        ),
      ),
    );
  }

  /// The menu, under the switcher and as wide as it.
  Widget _overlay(BuildContext context) => CompositedTransformFollower(
    link: _link,
    targetAnchor: Alignment.bottomLeft,
    followerAnchor: Alignment.topLeft,
    offset: const Offset(0, 6),
    showWhenUnlinked: false,
    child: Align(
      alignment: Alignment.topLeft,
      child: TapRegion(
        groupId: _group,
        onTapOutside: (_) => _shell.closeMenu(),
        child: SizedBox(
          width: Sizes.sidebar - 24,
          child: ListenableBuilder(
            listenable: Listenable.merge([
              _chat,
              AppScope.of(context).prefs,
              _shell,
            ]),
            builder: (context, _) => _WorkspaceMenu(
              onRename: () => widget.ask.ask(Asking.rename),
              onDelete: () => widget.ask.ask(Asking.delete),
              onCreate: () => widget.ask.ask(Asking.create),
            ),
          ),
        ),
      ),
    ),
  );
}

class _WorkspaceMenu extends StatelessWidget {
  const _WorkspaceMenu({
    required this.onRename,
    required this.onDelete,
    required this.onCreate,
  });

  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final shell = scope.shell;
    final t = Tokens.of(context);
    final ordered = scope.prefs.prefs.inOrder(chat.workspaces, (w) => w.slug);
    final active = chat.active;
    final keys = showsWorkspaceKeys(context);
    Widget divider() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Container(height: 1, color: t.line2),
    );
    return Material(
      color: t.panel,
      elevation: 8,
      shadowColor: t.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.line),
      ),
      child: Semantics(
        container: true,
        label: 'Workspaces',
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ordered.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
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
                    ),
                  ),
                ),
              if (ordered.isNotEmpty) divider(),
              _MenuItem(
                shell.pane == Pane.files ? 'Chats' : 'Files and settings',
                onTap: () => shell.showPane(
                  shell.pane == Pane.files ? Pane.chats : Pane.files,
                ),
              ),
              if (active != null) ...[
                _MenuItem('Rename workspace', onTap: onRename),
                _MenuItem(
                  'Delete workspace…',
                  danger: true,
                  onTap: chat.answeringIn(active.slug) ? null : onDelete,
                ),
              ],
              divider(),
              _MenuItem(
                'New workspace',
                icon: 'plus',
                accent: true,
                onTap: onCreate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the menu's actions.
class _MenuItem extends StatelessWidget {
  const _MenuItem(
    this.label, {
    required this.onTap,
    this.icon,
    this.danger = false,
    this.accent = false,
  });

  final String label;
  final VoidCallback? onTap;
  final String? icon;
  final bool danger;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final color = danger
        ? t.badfg
        : accent
        ? t.accent
        : t.ink;
    return Tappable(
      label: label,
      onTap: onTap,
      radius: BorderRadius.circular(8),
      dimWhenDisabled: 0.4,
      child: SizedBox(
        height: 38,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: icon == null
                    ? null
                    : AppIcon(icon!, size: IconSize.xs, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: Type.sans(14, color: color)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A workspace in the menu: tapped, it opens; dragged, it moves.
class _WorkspaceItem extends StatelessWidget {
  const _WorkspaceItem(
    this.workspace, {
    super.key,
    required this.index,
    this.shortcut,
  });

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
    return _Draggable(
      index: index,
      child: Tappable(
        label: workspace.name,
        selected: active,
        onTap: () {
          scope.shell.closeMenu();
          if (!active) chat.select(workspace.slug);
        },
        radius: BorderRadius.circular(8),
        color: active ? t.sel : null,
        child: SizedBox(
          height: 40,
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
                      14,
                      weight: active ? FontWeight.w600 : FontWeight.w400,
                      color: t.ink,
                    ),
                  ),
                ),
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
