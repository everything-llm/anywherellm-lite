import 'package:flutter/material.dart';

import '../core/copy.dart';
import '../core/find.dart';
import '../core/server_models.dart';
import 'app_scope.dart';
import 'files/file_tree.dart';
import 'icons.dart';
import 'layout.dart';
import 'state/chat_controller.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/basics.dart';
import 'widgets/brand.dart';
import 'widgets/buttons.dart';
import 'widgets/confirm_box.dart';
import 'widgets/fields.dart';
import 'widgets/inline_input.dart';
import 'widgets/min_height.dart';
import 'widgets/segmented.dart';
import 'widgets/settings_button.dart';
import 'widgets/tappable.dart';

/// The workspaces and the active one's chats, and the way to Settings.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      container: true,
      label: 'Workspaces',
      child: MinHeight(
        min: Sizes.panelMin,
        child: Container(
          width: Sizes.sidebar,
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
          decoration: BoxDecoration(
            color: t.side,
            border: Border(right: BorderSide(color: t.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 2, 8, 16),
                child: Align(alignment: Alignment.centerLeft, child: Brand()),
              ),
              const _PaneSwitch(),
              const SizedBox(height: 12),
              Expanded(
                child: ListenableBuilder(
                  listenable: AppScope.of(context).shell,
                  builder: (context, _) =>
                      AppScope.of(context).shell.pane == Pane.files
                      ? const FileTree()
                      : const _Workspaces(),
                ),
              ),
              const SizedBox(height: 8),
              const SidebarSettingsButton(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chats or Files: what the sidebar and the main pane show.
class _PaneSwitch extends StatelessWidget {
  const _PaneSwitch();

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    return ListenableBuilder(
      listenable: shell,
      builder: (context, _) => Segmented(
        options: const [(Pane.chats, 'Chats'), (Pane.files, 'Files')],
        value: shell.pane,
        onChanged: shell.showPane,
      ),
    );
  }
}

class _Workspaces extends StatefulWidget {
  const _Workspaces();

  @override
  State<_Workspaces> createState() => _WorkspacesState();
}

class _WorkspacesState extends State<_Workspaces> {
  bool _adding = false;
  final _name = TextEditingController();
  final _search = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  void _cancel() => setState(() {
    _adding = false;
    _name.clear();
  });

  Future<void> _create() async {
    final name = _name.text.trim();
    _cancel();
    if (name.isEmpty) return;
    final scope = AppScope.of(context);
    await scope.chat.createWorkspace(name);
    scope.shell.closeSide();
  }

  /// Moves a workspace in the arrangement the person keeps.
  void _reorder(List<Workspace> shown, int from, int to) {
    final slugs = [for (final w in shown) w.slug];
    slugs.insert(to, slugs.removeAt(from));
    AppScope.of(context).prefs.setWorkspaceOrder(slugs);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    return ListenableBuilder(
      listenable: Listenable.merge([chat, scope.prefs, _search]),
      builder: (context, _) {
        final query = _search.text.trim();
        final searching = query.isNotEmpty;
        final ordered = scope.prefs.prefs.inOrder(
          chat.workspaces,
          (w) => w.slug,
        );
        // A search keeps a workspace whose name matches, or that holds a chat whose name does.
        final shown = [
          for (final w in ordered)
            if (!searching ||
                matchesSearch(query, w.name) ||
                chat
                    .threadsOf(w.slug)
                    .any((thread) => matchesSearch(query, thread.name)))
              w,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SidebarSection(
              'Workspaces',
              action: IconBtn(
                'plus',
                tooltip: 'New workspace',
                box: 24,
                size: IconSize.xs,
                onPressed: () => setState(() => _adding = true),
              ),
            ),
            if (_adding)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InlineInput(
                  controller: _name,
                  label: 'New workspace name',
                  hint: 'Workspace name',
                  height: 36,
                  onSubmit: _create,
                  onCancel: _cancel,
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppField(
                controller: _search,
                label: 'Search workspaces and chats',
                hint: 'Search',
                icon: 'search',
                suffix: searching
                    ? IconBtn(
                        'close',
                        tooltip: 'Clear search',
                        box: 28,
                        size: IconSize.xs,
                        onPressed: _search.clear,
                      )
                    : null,
              ),
            ),
            Expanded(
              child: shown.isEmpty && searching
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Nothing matches "$query".',
                        style: Type.sans(13.5, color: Tokens.of(context).muted),
                      ),
                    )
                  : ReorderableListView.builder(
                      // The row's own header starts a drag, not the whole row.
                      buildDefaultDragHandles: false,
                      itemCount: shown.length,
                      onReorderItem: (from, to) => _reorder(shown, from, to),
                      // The dragged row is drawn in the app's overlay, outside AppScope, so
                      // it is shown as a name alone.
                      proxyDecorator: (child, i, animation) =>
                          _DragGhost(shown[i].name),
                      itemBuilder: (context, i) => _WorkspaceRow(
                        shown[i],
                        key: ValueKey(shown[i].slug),
                        index: i,
                        query: query,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _WorkspaceRow extends StatefulWidget {
  const _WorkspaceRow(
    this.workspace, {
    super.key,
    required this.index,
    required this.query,
  });

  final Workspace workspace;

  /// Where the row sits in the list, for dragging it to another place.
  final int index;

  /// What the sidebar is searching for. While it is not empty, every workspace shows its chats
  /// that match, and nothing can be dragged.
  final String query;

  @override
  State<_WorkspaceRow> createState() => _WorkspaceRowState();
}

class _WorkspaceRowState extends State<_WorkspaceRow> {
  TextEditingController? _rename;
  bool _confirming = false;
  late final ChatController _chat;

  Workspace get workspace => widget.workspace;

  @override
  void initState() {
    super.initState();
    _chat = AppScope.of(context).chat..addListener(_chatChanged);
  }

  @override
  void dispose() {
    _chat.removeListener(_chatChanged);
    _rename?.dispose();
    super.dispose();
  }

  /// Closes the delete question once the workspace is no longer on screen or starts answering,
  /// when Delete could no longer do what it asks.
  void _chatChanged() {
    final slug = workspace.slug;
    if (!_confirming ||
        (_chat.activeSlug == slug && !_chat.answeringIn(slug))) {
      return;
    }
    setState(() => _confirming = false);
  }

  void _startRename() => setState(
    () => _rename = TextEditingController(text: workspace.name)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: workspace.name.length,
      ),
  );

  void _endRename() {
    final controller = _rename;
    setState(() => _rename = null);
    controller?.dispose();
  }

  Future<void> _commit() async {
    final name = _rename?.text.trim() ?? '';
    _endRename();
    if (name.isNotEmpty && name != workspace.name) {
      await AppScope.of(context).chat.renameWorkspace(workspace.slug, name);
    }
  }

  Widget _header(BuildContext context, {required bool active}) {
    final chat = AppScope.of(context).chat;
    final t = Tokens.of(context);
    final rename = _rename;
    if (rename != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: InlineInput(
          controller: rename,
          label: 'Workspace name',
          height: 32,
          maxLength: 80,
          onSubmit: _commit,
          onCancel: _endRename,
          commitOnBlur: true,
        ),
      );
    }
    if (_confirming) {
      final chats = chat.threadsOf(workspace.slug).length;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ConfirmBox(
          text:
              'Delete ${workspace.name} and its ${plural(chats, 'chat', 'chats')}? Its documents stay in the library.',
          onCancel: () => setState(() => _confirming = false),
          onConfirm: () {
            setState(() => _confirming = false);
            chat.deleteWorkspace(workspace.slug);
          },
        ),
      );
    }
    final count = chat.docCounts[workspace.slug];
    return Container(
      decoration: BoxDecoration(
        color: active ? t.sel : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Draggable(
              index: widget.index,
              enabled: widget.query.isEmpty,
              child: Tappable(
                label: workspace.name,
                selected: active,
                tooltip: active ? 'Double-click to rename' : null,
                onTap: () {
                  if (!active) chat.select(workspace.slug);
                },
                onDoubleTap: active ? _startRename : null,
                radius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      AppIcon('chat', size: IconSize.small, color: t.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          workspace.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Type.sans(
                            14.5,
                            weight: active ? FontWeight.w600 : FontWeight.w400,
                            color: t.ink,
                          ),
                        ),
                      ),
                      if (count != null && count > 0)
                        Text(
                          plural(count, 'doc', 'docs'),
                          style: Type.sans(12, color: t.muted),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (active) ...[
            IconBtn(
              'pencil',
              tooltip: 'Rename workspace',
              box: 28,
              size: IconSize.xs,
              onPressed: _startRename,
            ),
            IconBtn(
              'trash',
              tooltip: 'Delete workspace',
              box: 28,
              size: IconSize.xs,
              dangerHover: true,
              onPressed: chat.answeringIn(workspace.slug)
                  ? null
                  : () => setState(() => _confirming = true),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final t = Tokens.of(context);
    final active = chat.activeSlug == workspace.slug;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, active: active),
        if (active && widget.query.isEmpty) ...[
          Tappable(
            label: 'New chat',
            onTap: () {
              chat.newChat();
              scope.shell.closeSide();
            },
            radius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 6, 10, 6),
              child: Row(
                children: [
                  AppIcon('plus', size: IconSize.xs, color: t.accent),
                  const SizedBox(width: 6),
                  Text('New chat', style: Type.sans(13.5, color: t.accent)),
                ],
              ),
            ),
          ),
          for (final thread in chat.threadsOf(workspace.slug).reversed)
            _ChatRow(
              thread,
              workspace: workspace.slug,
              current: chat.activeThread == thread.slug,
            ),
        ] else if (widget.query.isNotEmpty)
          for (final thread in chat.threadsOf(workspace.slug).reversed)
            if (matchesSearch(widget.query, thread.name))
              _ChatRow(
                thread,
                workspace: workspace.slug,
                current: active && chat.activeThread == thread.slug,
              ),
      ],
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            AppIcon('chat', size: IconSize.small, color: t.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.sans(14.5, weight: FontWeight.w600, color: t.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Starts dragging its [child] to another place in the list: at once with a mouse, after a
/// press and hold on a touch screen, which would otherwise scroll.
class _Draggable extends StatelessWidget {
  const _Draggable({
    required this.index,
    required this.enabled,
    required this.child,
  });

  final int index;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia =>
        ReorderableDelayedDragStartListener(index: index, child: child),
      _ => ReorderableDragStartListener(index: index, child: child),
    };
  }
}

class _ChatRow extends StatefulWidget {
  const _ChatRow(this.thread, {required this.workspace, required this.current});

  final Thread thread;

  /// The slug of the workspace the chat belongs to, which a search can show without it being
  /// the one on screen.
  final String workspace;
  final bool current;

  @override
  State<_ChatRow> createState() => _ChatRowState();
}

class _ChatRowState extends State<_ChatRow> {
  TextEditingController? _rename;

  @override
  void dispose() {
    _rename?.dispose();
    super.dispose();
  }

  void _startRename() => setState(
    () => _rename = TextEditingController(text: widget.thread.name)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.thread.name.length,
      ),
  );

  void _endRename() {
    final controller = _rename;
    setState(() => _rename = null);
    controller?.dispose();
  }

  Future<void> _commit() async {
    final name = _rename?.text.trim() ?? '';
    _endRename();
    if (name.isNotEmpty && name != widget.thread.name) {
      await AppScope.of(context).chat.rename(widget.thread.slug, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final rename = _rename;
    if (rename != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(30, 2, 0, 2),
        child: InlineInput(
          controller: rename,
          label: 'Chat name',
          height: 28,
          maxLength: 60,
          onSubmit: _commit,
          onCancel: _endRename,
          commitOnBlur: true,
        ),
      );
    }
    final busy = scope.chat.isAnswering(widget.thread.slug);
    return Container(
      decoration: BoxDecoration(
        color: widget.current ? t.sel : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Tappable(
              label: widget.thread.name,
              selected: widget.current,
              tooltip: widget.current ? 'Double-click to rename' : null,
              onTap: () async {
                final chat = scope.chat;
                scope.shell.closeSide();
                if (chat.activeSlug != widget.workspace) {
                  await chat.select(widget.workspace);
                }
                await chat.open(widget.thread.slug);
              },
              onDoubleTap: widget.current ? _startRename : null,
              radius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(36, 7, 4, 7),
                child: Text(
                  widget.thread.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sans(
                    13.5,
                    weight: widget.current ? FontWeight.w600 : FontWeight.w400,
                    color: t.ink,
                  ),
                ),
              ),
            ),
          ),
          if (widget.current) ...[
            IconBtn(
              'pencil',
              tooltip: 'Rename chat',
              box: 28,
              size: IconSize.xs,
              onPressed: _startRename,
            ),
            IconBtn(
              'trash',
              tooltip: 'Delete chat',
              box: 28,
              size: IconSize.xs,
              dangerHover: true,
              onPressed: busy
                  ? null
                  : () => scope.chat.delete(widget.thread.slug),
            ),
          ],
        ],
      ),
    );
  }
}
