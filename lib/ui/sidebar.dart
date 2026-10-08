import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/chat_groups.dart';
import '../core/copy.dart';
import '../core/find.dart';
import '../core/server_models.dart';
import 'app_scope.dart';
import 'files/file_tree.dart';
import 'icons.dart';
import 'layout.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/brand.dart';
import 'widgets/buttons.dart';
import 'widgets/fields.dart';
import 'widgets/inline_input.dart';
import 'widgets/min_height.dart';
import 'widgets/settings_button.dart';
import 'widgets/tappable.dart';
import 'workspace_switcher.dart';

/// The open workspace's switcher, its chats or the server's files, and the way to Settings.
class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  late final WorkspaceAsk _ask;

  @override
  void initState() {
    super.initState();
    final scope = AppScope.of(context);
    _ask = WorkspaceAsk(scope.chat, scope.shell);
  }

  @override
  void dispose() {
    _ask.dispose();
    super.dispose();
  }

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
              WorkspaceSwitcher(_ask),
              const SizedBox(height: 12),
              Expanded(
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    AppScope.of(context).shell,
                    _ask,
                  ]),
                  builder: (context, _) => switch (_ask.asking) {
                    Asking.delete || Asking.create => WorkspaceQuestion(_ask),
                    _ when AppScope.of(context).shell.pane == Pane.files =>
                      const _Files(),
                    _ => const _Chats(),
                  },
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

/// The server's files, under the way back to the chats.
class _Files extends StatelessWidget {
  const _Files();

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextAction(
            'back',
            'Back to chats',
            () => shell.showPane(Pane.chats),
          ),
        ),
        const SizedBox(height: 4),
        const Expanded(child: FileTree()),
      ],
    );
  }
}

/// New chat, the search, and the open workspace's chats: pinned, then the ones this device
/// used last, then the rest. A search lists every workspace whose name matches, and the
/// matching chats of every workspace under their workspace's name.
class _Chats extends StatefulWidget {
  const _Chats();

  @override
  State<_Chats> createState() => _ChatsState();
}

class _ChatsState extends State<_Chats> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([chat, scope.prefs, _search]),
      builder: (context, _) {
        final query = _search.text.trim();
        final searching = query.isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!searching && chat.active != null)
              Tappable(
                label: 'New chat',
                onTap: () {
                  chat.newChat();
                  scope.shell.closeSide();
                },
                radius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 40,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        AppIcon('plus', size: IconSize.xs, color: t.ink2),
                        const SizedBox(width: 10),
                        Text(
                          'New chat',
                          style: Type.sans(
                            14,
                            weight: FontWeight.w500,
                            color: t.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: AppField(
                controller: _search,
                focusNode: scope.shell.searchFocus,
                label: 'Search workspaces and chats',
                hint: 'Search chats',
                icon: 'search',
                suffix: searching
                    ? IconBtn(
                        'close',
                        tooltip: 'Clear search',
                        box: 28,
                        size: IconSize.xs,
                        onPressed: _search.clear,
                      )
                    : showsWorkspaceKeys(context)
                    ? const _KeyHint('Ctrl K')
                    : null,
              ),
            ),
            Expanded(
              child: searching ? _found(context, query) : _groups(context),
            ),
          ],
        );
      },
    );
  }

  /// The open workspace's chats in their groups.
  Widget _groups(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final slug = chat.activeSlug;
    if (slug == null) return const SizedBox.shrink();
    final groups = groupChats(
      chat.threadsOf(slug),
      scope.prefs.pinnedIn(slug),
      scope.prefs.recentIn(slug),
    );
    final pins = groups.pinned.map((t) => t.slug).toSet();
    Iterable<Widget> rows(List<Thread> threads) => [
      for (final thread in threads)
        _ChatRow(
          thread,
          key: ValueKey(thread.slug),
          workspace: slug,
          current: chat.activeThread == thread.slug,
          pinned: pins.contains(thread.slug),
        ),
    ];
    final mixed = groups.pinned.isNotEmpty || groups.recent.isNotEmpty;
    return ListView(
      children: [
        if (groups.pinned.isNotEmpty) ...[
          const _GroupLabel('Pinned'),
          ...rows(groups.pinned),
        ],
        if (groups.recent.isNotEmpty) ...[
          const _GroupLabel('Recent', hint: 'on this device'),
          ...rows(groups.recent),
        ],
        if (groups.rest.isNotEmpty) ...[
          if (mixed) const _GroupLabel('All chats'),
          ...rows(groups.rest),
        ],
      ],
    );
  }

  /// What [query] finds: each workspace whose name or a chat of which matches, with its
  /// matching chats under it.
  Widget _found(BuildContext context, String query) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final ordered = scope.prefs.prefs.inOrder(chat.workspaces, (w) => w.slug);
    final found = [
      for (final w in ordered)
        (
          w,
          [
            for (final thread in chat.threadsOf(w.slug).reversed)
              if (matchesSearch(query, thread.name)) thread,
          ],
        ),
    ].where((f) => matchesSearch(query, f.$1.name) || f.$2.isNotEmpty);
    if (found.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'Nothing matches "$query".',
          style: Type.sans(13.5, color: Tokens.of(context).muted),
        ),
      );
    }
    return ListView(
      children: [
        for (final (workspace, threads) in found) ...[
          _FoundWorkspace(workspace),
          for (final thread in threads)
            _ChatRow(
              thread,
              key: ValueKey(thread.slug),
              workspace: workspace.slug,
              current:
                  chat.activeSlug == workspace.slug &&
                  chat.activeThread == thread.slug,
              pinned: scope.prefs
                  .pinnedIn(workspace.slug)
                  .contains(thread.slug),
              indent: true,
            ),
        ],
      ],
    );
  }
}

/// The keys that move to a field, drawn small inside it.
class _KeyHint extends StatelessWidget {
  const _KeyHint(this.keys);

  final String keys;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(keys, style: Type.sans(11, color: t.muted)),
        ),
      ),
    );
  }
}

/// A group's name over its chats, with a lighter [hint] after it.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label, {this.hint});

  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
        child: Text.rich(
          TextSpan(
            text: label,
            style: Type.sans(12, weight: FontWeight.w500, color: t.muted),
            children: [
              if (hint != null)
                TextSpan(
                  text: '  $hint',
                  style: Type.sans(12, color: t.fade),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A workspace a search found: tapped, it opens.
class _FoundWorkspace extends StatelessWidget {
  const _FoundWorkspace(this.workspace);

  final Workspace workspace;

  @override
  Widget build(BuildContext context) {
    final chat = AppScope.of(context).chat;
    final t = Tokens.of(context);
    final active = chat.activeSlug == workspace.slug;
    final count = chat.docCounts[workspace.slug];
    return Tappable(
      label: workspace.name,
      selected: active,
      onTap: () {
        if (!active) chat.select(workspace.slug);
      },
      radius: BorderRadius.circular(8),
      color: active ? t.sel : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
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
    );
  }
}

class _ChatRow extends StatefulWidget {
  const _ChatRow(
    this.thread, {
    super.key,
    required this.workspace,
    required this.current,
    required this.pinned,
    this.indent = false,
  });

  final Thread thread;

  /// The slug of the workspace the chat belongs to, which a search can show without it being
  /// the one on screen.
  final String workspace;
  final bool current;
  final bool pinned;

  /// Set under a workspace a search found.
  final bool indent;

  @override
  State<_ChatRow> createState() => _ChatRowState();
}

class _ChatRowState extends State<_ChatRow> {
  TextEditingController? _rename;
  final _menu = OverlayPortalController();
  final _link = LayerLink();
  final _group = Object();

  @override
  void dispose() {
    _rename?.dispose();
    super.dispose();
  }

  void _startRename() {
    if (_menu.isShowing) _menu.hide();
    setState(
      () => _rename = TextEditingController(text: widget.thread.name)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.thread.name.length,
        ),
    );
  }

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
    final left = widget.indent ? 36.0 : 10.0;
    if (rename != null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(left - 6, 2, 0, 2),
        child: InlineInput(
          controller: rename,
          label: 'Chat name',
          height: 32,
          maxLength: 60,
          onSubmit: _commit,
          onCancel: _endRename,
          commitOnBlur: true,
        ),
      );
    }
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
                  await chat.select(
                    widget.workspace,
                    thread: widget.thread.slug,
                  );
                } else {
                  await chat.open(widget.thread.slug);
                }
              },
              onDoubleTap: widget.current ? _startRename : null,
              radius: BorderRadius.circular(8),
              child: Padding(
                padding: EdgeInsets.fromLTRB(left, 8, 4, 8),
                child: Row(
                  children: [
                    if (widget.pinned) ...[
                      Semantics(
                        label: 'Pinned',
                        child: AppIcon(
                          'pin',
                          size: IconSize.xs,
                          color: t.muted,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        widget.thread.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.sans(
                          14,
                          weight: widget.current
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: t.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.current)
            TapRegion(
              groupId: _group,
              child: CompositedTransformTarget(
                link: _link,
                child: OverlayPortal(
                  controller: _menu,
                  overlayChildBuilder: _overlay,
                  child: IconBtn(
                    'more',
                    tooltip: 'Chat actions: rename, pin, delete',
                    box: 30,
                    size: IconSize.xs,
                    onPressed: _menu.toggle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The chat's actions, under its ⋯ and ending at its right edge.
  Widget _overlay(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final t = Tokens.of(context);
    final thread = widget.thread.slug;
    void act(VoidCallback action) {
      _menu.hide();
      action();
    }

    return CompositedTransformFollower(
      link: _link,
      targetAnchor: Alignment.bottomRight,
      followerAnchor: Alignment.topRight,
      offset: const Offset(0, 4),
      showWhenUnlinked: false,
      child: Align(
        alignment: Alignment.topRight,
        child: TapRegion(
          groupId: _group,
          onTapOutside: (_) => _menu.hide(),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): _menu.hide,
            },
            child: Focus(
              autofocus: true,
              child: SizedBox(
                width: 200,
                child: Material(
                  color: t.panel,
                  elevation: 8,
                  shadowColor: t.shadow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: t.line),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _RowAction(
                          'Rename chat',
                          icon: 'pencil',
                          onTap: () => act(_startRename),
                        ),
                        _RowAction(
                          widget.pinned ? 'Unpin chat' : 'Pin chat',
                          icon: 'pin',
                          onTap: () => act(
                            () => scope.prefs.setPinned(
                              widget.workspace,
                              thread,
                              on: !widget.pinned,
                            ),
                          ),
                        ),
                        _RowAction(
                          'Delete chat',
                          icon: 'trash',
                          danger: true,
                          onTap: chat.isAnswering(thread)
                              ? null
                              : () => act(() => chat.delete(thread)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of a chat's actions.
class _RowAction extends StatelessWidget {
  const _RowAction(
    this.label, {
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final String icon;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final color = danger ? t.badfg : t.ink;
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
              AppIcon(icon, size: IconSize.xs, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sans(14, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
