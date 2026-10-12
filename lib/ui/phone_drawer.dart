import 'package:flutter/material.dart';

import '../core/chat_groups.dart';
import '../core/copy.dart';
import '../core/find.dart';
import '../core/server_models.dart';
import 'activity.dart';
import 'app_scope.dart';
import 'icons.dart';
import 'layout.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'type.dart';
import 'upcoming.dart';
import 'widgets/basics.dart';
import 'widgets/buttons.dart';
import 'widgets/drawer_row.dart';
import 'widgets/min_height.dart';
import 'widgets/tappable.dart';
import 'workspace_switcher.dart';

/// A phone's drawer, in flat rows on its ground as the design canvas draws it: the workspace
/// switcher beside Workspace settings; the search, New chat and the open workspace's chats under
/// Chats, each with a More button that opens its sheet; then, under a hairline, Activity,
/// Upcoming and Settings. Only the chats scroll, unless the drawer is shorter than
/// [minHeight].
class PhoneDrawer extends StatefulWidget {
  const PhoneDrawer({super.key, required this.width});

  final double width;

  /// The least height the drawer is laid out at, room for its fixed rows and a few chats;
  /// shorter, it scrolls whole. A fixed row added to the drawer needs it raised.
  static const minHeight = 480.0;

  @override
  State<PhoneDrawer> createState() => _PhoneDrawerState();
}

class _PhoneDrawerState extends State<PhoneDrawer> {
  final _search = TextEditingController();

  /// What the search holds, trimmed: it changes only with the words, not with the cursor.
  final _query = ValueNotifier('');

  @override
  void initState() {
    super.initState();
    _search.addListener(() => _query.value = _search.text.trim());
  }

  @override
  void dispose() {
    _search.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final shell = scope.shell;
    final t = Tokens.of(context);
    return Semantics(
      container: true,
      label: 'Workspaces',
      child: Container(
        width: widget.width,
        color: t.side,
        child: MinHeight(
          min: PhoneDrawer.minHeight,
          child: ListenableBuilder(
            listenable: Listenable.merge([
              chat,
              scope.prefs,
              scope.settings,
              _query,
            ]),
            builder: (context, _) {
              final query = _query.value;
              final searching = query.isNotEmpty;
              final active = chat.active;
              return Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 2,
                  children: [
                    SizedBox(
                      height: 52,
                      child: Row(
                        children: [
                          const Expanded(child: PhoneWorkspaceSwitcher()),
                          if (active != null)
                            IconBtn(
                              'settings',
                              tooltip: 'Workspace settings',
                              box: 44,
                              onPressed: () {
                                shell
                                  ..closeSide()
                                  ..showPane(Pane.files);
                              },
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 6),
                      child: _Search(_search, focus: shell.searchFocus),
                    ),
                    if (!searching && active != null) ...[
                      DrawerRow(
                        icon: 'plus',
                        title: 'New chat',
                        heard: 'New chat',
                        iconSize: IconSize.small,
                        onTap: () {
                          chat.newChat();
                          shell.closeSide();
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
                        child: Semantics(
                          header: true,
                          child: Text(
                            'Chats',
                            style: Type.sans(12.5, color: t.muted),
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: searching
                            ? _found(context, query)
                            : _chats(context),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: t.line)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 2,
                        children: [
                          if (scope.settings.configured) ...const [
                            ActivityRow(),
                            UpcomingRow(),
                          ],
                          DrawerRow(
                            icon: 'settings',
                            title: 'Settings',
                            heard: 'Settings',
                            onTap: () => shell.openSettings(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// The open workspace's chats: the pinned ones, then the ones this device used last, then
  /// the rest.
  List<Widget> _chats(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final slug = chat.activeSlug;
    if (slug == null) return const [];
    final groups = groupChats(
      chat.threadsOf(slug),
      scope.prefs.pinnedIn(slug),
      scope.prefs.recentIn(slug),
    );
    return [
      for (final thread in groups.pinned)
        _ChatRow(thread, workspace: slug, pinned: true),
      for (final thread in [...groups.recent, ...groups.rest])
        _ChatRow(thread, workspace: slug, pinned: false),
    ];
  }

  /// What [query] finds: each workspace whose name or a chat of which matches, with its
  /// matching chats under it.
  List<Widget> _found(BuildContext context, String query) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final t = Tokens.of(context);
    final ordered = scope.prefs.prefs.inOrder(chat.workspaces, (w) => w.slug);
    final found = findChats(query, ordered, chat.threadsOf);
    if (found.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Nothing matches "$query".',
            style: Type.sans(15.5, color: t.muted),
          ),
        ),
      ];
    }
    return [
      for (final (workspace, threads) in found) ...[
        _FoundWorkspace(workspace),
        for (final thread in threads)
          _ChatRow(
            thread,
            workspace: workspace.slug,
            pinned: scope.prefs.pinnedIn(workspace.slug).contains(thread.slug),
          ),
      ],
    ];
  }
}

/// The search: a filled row of the drawer.
class _Search extends StatelessWidget {
  const _Search(this.controller, {required this.focus});

  final TextEditingController controller;
  final FocusNode focus;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final searching = controller.text.isNotEmpty;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: EdgeInsets.only(left: 12, right: searching ? 0 : 12),
      decoration: BoxDecoration(
        color: t.hover,
        borderRadius: BorderRadius.circular(Sizes.control),
      ),
      child: Row(
        spacing: 10,
        children: [
          AppIcon('search', size: IconSize.small, color: t.muted),
          Expanded(
            child: Semantics(
              label: 'Search workspaces and chats',
              textField: true,
              child: TextField(
                controller: controller,
                focusNode: focus,
                autocorrect: false,
                style: Type.sans(15.5, color: t.ink),
                cursorColor: t.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search chats',
                  hintStyle: Type.sans(15.5, color: t.muted),
                ),
              ),
            ),
          ),
          if (searching)
            IconBtn(
              'close',
              tooltip: 'Clear search',
              box: 44,
              size: IconSize.xs,
              onPressed: controller.clear,
            ),
        ],
      ),
    );
  }
}

/// A workspace the search found: tapped, it opens.
class _FoundWorkspace extends StatelessWidget {
  const _FoundWorkspace(this.workspace);

  final Workspace workspace;

  @override
  Widget build(BuildContext context) {
    final chat = AppScope.of(context).chat;
    final active = chat.activeSlug == workspace.slug;
    final count = chat.docCounts[workspace.slug];
    return DrawerRow(
      icon: 'chat',
      title: workspace.name,
      heard: workspace.name,
      iconSize: IconSize.small,
      selected: active,
      strong: true,
      trailing: count != null && count > 0
          ? DrawerCount(plural(count, 'doc', 'docs'))
          : null,
      onTap: () {
        if (!active) chat.select(workspace.slug);
      },
    );
  }
}

/// A chat in the drawer: its name, after it its pin and whether its answer is ready, and a More
/// button that opens its sheet. The chat on screen is filled.
class _ChatRow extends StatelessWidget {
  const _ChatRow(this.thread, {required this.workspace, required this.pinned});

  final Thread thread;
  final String workspace;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final t = Tokens.of(context);
    final current =
        chat.activeSlug == workspace && chat.activeThread == thread.slug;
    final ready = chat.isReady(thread.slug);
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: current ? t.sel : null,
        borderRadius: BorderRadius.circular(Sizes.control),
      ),
      child: Row(
        children: [
          Expanded(
            child: Tappable(
              label: [
                thread.name,
                if (pinned) 'pinned',
                if (ready) 'answer ready',
              ].join(', '),
              selected: current,
              radius: BorderRadius.circular(Sizes.control),
              onTap: () async {
                scope.shell.closeSide();
                if (chat.activeSlug != workspace) {
                  await chat.select(workspace, thread: thread.slug);
                } else {
                  await chat.open(thread.slug);
                }
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    spacing: 6,
                    children: [
                      Flexible(
                        child: Text(
                          thread.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Type.sans(
                            15.5,
                            weight: current ? FontWeight.w600 : FontWeight.w400,
                            color: t.ink,
                          ),
                        ),
                      ),
                      if (pinned)
                        AppIcon('pin', size: IconSize.xs, color: t.muted),
                      if (ready) const ReadyDot(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // A chat's sheet acts on the workspace on screen.
          if (workspace == chat.activeSlug)
            IconBtn(
              'more',
              tooltip: 'Rename, pin or delete ${thread.name}',
              box: 44,
              size: IconSize.small,
              onPressed: () => scope.shell.openChatSheet(thread),
            ),
        ],
      ),
    );
  }
}
