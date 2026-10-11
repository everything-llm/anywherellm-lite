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
import 'widgets/tappable.dart';
import 'workspace_switcher.dart';

/// A phone's drawer, in cards as the design canvas draws it: the workspace switcher and
/// Workspace settings; New chat, the search and the open workspace's chats, each with a More
/// button that opens its sheet; then, under All workspaces, Activity, Upcoming and App
/// settings. The whole drawer scrolls.
class PhoneDrawer extends StatefulWidget {
  const PhoneDrawer({super.key, required this.width});

  final double width;

  @override
  State<PhoneDrawer> createState() => _PhoneDrawerState();
}

class _PhoneDrawerState extends State<PhoneDrawer> {
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
    final shell = scope.shell;
    final t = Tokens.of(context);
    return Semantics(
      container: true,
      label: 'Workspaces',
      child: Container(
        width: widget.width,
        color: t.side,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            chat,
            scope.prefs,
            scope.settings,
            _search,
          ]),
          builder: (context, _) {
            final query = _search.text.trim();
            final searching = query.isNotEmpty;
            final active = chat.active;
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                  child: Text(
                    'AnywhereLLM',
                    style: Type.sans(19, weight: FontWeight.w700, color: t.ink),
                  ),
                ),
                DrawerCard([
                  const PhoneWorkspaceSwitcher(),
                  if (active != null)
                    DrawerRow(
                      icon: 'settings',
                      title: 'Workspace settings',
                      heard: 'Workspace settings',
                      trailing: AppIcon(
                        'chevron',
                        size: IconSize.xs,
                        color: t.muted,
                      ),
                      onTap: () {
                        shell
                          ..closeSide()
                          ..showPane(Pane.files);
                      },
                    ),
                ]),
                const SizedBox(height: 14),
                DrawerCard([
                  if (!searching && active != null)
                    DrawerRow(
                      icon: 'plus',
                      title: 'New chat',
                      heard: 'New chat',
                      accent: true,
                      onTap: () {
                        chat.newChat();
                        shell.closeSide();
                      },
                    ),
                  _Search(_search, focus: shell.searchFocus),
                  ...searching ? _found(context, query) : _chats(context),
                ]),
                if (scope.settings.configured) ...[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Semantics(
                      header: true,
                      child: Text(
                        'All workspaces',
                        style: Type.sans(
                          12,
                          weight: FontWeight.w500,
                          color: t.muted,
                        ),
                      ),
                    ),
                  ),
                ],
                if (!scope.settings.configured) const SizedBox(height: 14),
                DrawerCard([
                  if (scope.settings.configured) ...const [
                    ActivityRow(),
                    UpcomingRow(),
                  ],
                  DrawerRow(
                    icon: 'settings',
                    title: 'App settings',
                    heard: 'App settings',
                    onTap: () => shell.openSettings(),
                  ),
                ]),
              ],
            );
          },
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
            style: Type.sans(15, color: t.muted),
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

/// A card of a phone's drawer: its [rows] on the panel, a hairline between each.
class DrawerCard extends StatelessWidget {
  const DrawerCard(this.rows, {super.key});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: t.panel,
        border: Border.all(color: t.line2),
        borderRadius: BorderRadius.circular(Sizes.phoneCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: t.line2),
            row,
          ],
        ],
      ),
    );
  }
}

/// The search, as a row of the drawer's card.
class _Search extends StatelessWidget {
  const _Search(this.controller, {required this.focus});

  final TextEditingController controller;
  final FocusNode focus;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final searching = controller.text.isNotEmpty;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          spacing: 16,
          children: [
            AppIcon('search', color: t.muted),
            Expanded(
              child: Semantics(
                label: 'Search workspaces and chats',
                textField: true,
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  autocorrect: false,
                  style: Type.sans(17, color: t.ink),
                  cursorColor: t.accent,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Search chats',
                    hintStyle: Type.sans(17, color: t.muted),
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
    final t = Tokens.of(context);
    final active = chat.activeSlug == workspace.slug;
    final count = chat.docCounts[workspace.slug];
    return Tappable(
      label: workspace.name,
      selected: active,
      onTap: () {
        if (!active) chat.select(workspace.slug);
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            spacing: 16,
            children: [
              AppIcon('chat', color: t.muted),
              Expanded(
                child: Text(
                  workspace.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sans(17, weight: FontWeight.w600, color: t.ink),
                ),
              ),
              if (count != null && count > 0)
                Text(
                  plural(count, 'doc', 'docs'),
                  style: Type.sans(13, color: t.muted),
                ),
            ],
          ),
        ),
      ),
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
    return ColoredBox(
      color: current ? t.sel : Colors.transparent,
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
              onTap: () async {
                scope.shell.closeSide();
                if (chat.activeSlug != workspace) {
                  await chat.select(workspace, thread: thread.slug);
                } else {
                  await chat.open(thread.slug);
                }
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    spacing: 8,
                    children: [
                      Flexible(
                        child: Text(
                          thread.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Type.sans(
                            17,
                            weight: current ? FontWeight.w600 : FontWeight.w400,
                            color: t.ink,
                          ),
                        ),
                      ),
                      if (pinned)
                        AppIcon('pin', size: IconSize.small, color: t.muted),
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
