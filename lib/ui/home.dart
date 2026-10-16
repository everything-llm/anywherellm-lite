import 'package:flutter/material.dart';

import '../core/chat_groups.dart';
import '../core/copy.dart';
import '../core/find.dart';
import '../core/server_models.dart';
import 'app_scope.dart';
import 'icons.dart';
import 'layout.dart';
import 'settings/rows.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'type.dart';
import 'toolkit_card.dart';
import 'widgets/basics.dart';
import 'widgets/buttons.dart';
import 'widgets/min_height.dart';
import 'widgets/phone_page.dart';
import 'widgets/tappable.dart';
import 'workspace_switcher.dart';

/// The chats list, drawn in the shelf: the open workspace's name as its title, which opens the Workspaces sheet,
/// with Workspace settings and New chat beside it; the search; the toolkit's card; then the
/// workspace's chats under Chats, each with a More button that opens its sheet. A chat opens in
/// the chat and closes the shelf.
class ChatsList extends StatefulWidget {
  const ChatsList({super.key});

  @override
  State<ChatsList> createState() => _ChatsListState();
}

class _ChatsListState extends State<ChatsList> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Search chats');

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
    _searchFocus.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final shell = scope.shell;
    return Semantics(
      container: true,
      label: 'Chats',
      child: MinHeight(
        min: Sizes.panelMin,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Sizes.header),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 0),
                child: Row(
                  children: [
                    const Expanded(child: WorkspaceSwitcher()),
                    ListenableBuilder(
                      listenable: chat,
                      builder: (context, _) => Row(
                        // A gap after the title, then between the buttons.
                        spacing: 8,
                        children: [
                          if (chat.active != null) ...[
                            const SizedBox.shrink(),
                            IconBtn(
                              'settings',
                              tooltip: 'Workspace settings',
                              box: 48,
                              filled: true,
                              onPressed: () => shell.showPane(Pane.files),
                            ),
                            IconBtn(
                              'plus',
                              tooltip: 'New chat',
                              box: 48,
                              filled: true,
                              onPressed: () {
                                chat.newChat();
                                shell.openChat();
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  chat,
                  scope.prefs,
                  scope.settings,
                  _query,
                ]),
                builder: (context, _) {
                  final query = _query.value;
                  return CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: Sizes.pagePadding,
                        sliver: SliverMainAxisGroup(
                          slivers: [
                            SliverToBoxAdapter(
                              child: _Search(_search, focus: _searchFocus),
                            ),
                            if (query.isNotEmpty)
                              SliverToBoxAdapter(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: _found(context, query),
                                ),
                              )
                            else ...[
                              if (scope.settings.configured)
                                const SliverToBoxAdapter(child: ToolkitCard()),
                              if (chat.activeSlug case final slug?) ...[
                                const SliverToBoxAdapter(
                                  child: CardHeading('Chats'),
                                ),
                                _chats(context, slug),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The open workspace's chats, built as they scroll into view: the pinned ones, then the
  /// ones this device used last, then the rest.
  Widget _chats(BuildContext context, String slug) {
    final scope = AppScope.of(context);
    final groups = groupChats(
      scope.chat.threadsOf(slug),
      scope.prefs.pinnedIn(slug),
      scope.prefs.recentIn(slug),
    );
    final rows = [
      for (final thread in groups.pinned) (thread, true),
      for (final thread in [...groups.recent, ...groups.rest]) (thread, false),
    ];
    if (rows.isEmpty) {
      return const SliverToBoxAdapter(
        child: FieldCard([CardNote('No chats yet.')]),
      );
    }
    return SliverFieldCard(
      count: rows.length,
      keyOf: (i) => ValueKey(rows[i].$1.slug),
      row: (context, i) =>
          _ChatRow(rows[i].$1, workspace: slug, pinned: rows[i].$2),
    );
  }

  /// What [query] finds: each workspace whose name or a chat of which matches, in a card with
  /// its matching chats under it.
  List<Widget> _found(BuildContext context, String query) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final ordered = scope.prefs.prefs.inOrder(chat.workspaces, (w) => w.slug);
    final found = findChats(query, ordered, chat.threadsOf);
    if (found.isEmpty) {
      return [
        const SizedBox(height: 20),
        FieldCard([CardNote('Nothing matches "$query".')]),
      ];
    }
    return [
      for (final (workspace, threads) in found) ...[
        const SizedBox(height: 20),
        FieldCard([
          _FoundWorkspace(workspace),
          for (final thread in threads)
            _ChatRow(
              thread,
              workspace: workspace.slug,
              pinned: scope.prefs
                  .pinnedIn(workspace.slug)
                  .contains(thread.slug),
            ),
        ]),
      ],
    ];
  }
}

/// The search: a field on the panel inside a [Tokens.line] edge, which turns [Tokens.ink]
/// while it has the focus.
class _Search extends StatelessWidget {
  const _Search(this.controller, {required this.focus});

  final TextEditingController controller;
  final FocusNode focus;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final searching = controller.text.isNotEmpty;
    return ListenableBuilder(
      listenable: focus,
      builder: (context, child) => Container(
        // Its edge sits outside the field's height, as the Lite prototype draws it.
        constraints: const BoxConstraints(minHeight: Sizes.field + 2),
        padding: EdgeInsets.only(left: 16, right: searching ? 4 : 16),
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(Sizes.control),
          border: Border.all(color: focus.hasFocus ? t.ink : t.line),
        ),
        child: child,
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
                style: Type.sans(16, color: t.ink),
                cursorColor: t.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search chats',
                  hintStyle: Type.sans(16, color: t.muted),
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
    return NavRow(
      icon: 'grid',
      title: workspace.name,
      about: count != null && count > 0 ? plural(count, 'doc', 'docs') : null,
      heard: workspace.name,
      selected: active,
      chevron: false,
      onTap: () {
        if (!active) chat.select(workspace.slug);
      },
    );
  }
}

/// A chat in the chats list: its name, after it its pin and whether its answer is ready, and a
/// More button that opens its sheet. Tapped, it opens in the chat.
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
    final ready = chat.isReady(thread.slug);
    return Padding(
      padding: const EdgeInsets.only(left: FieldCard.inset, right: 8),
      child: Row(
        children: [
          Expanded(
            child: Tappable(
              label: [
                thread.name,
                if (pinned) 'pinned',
                if (ready) 'answer ready',
              ].join(', '),
              onTap: () async {
                scope.shell.openChat();
                if (chat.activeSlug != workspace) {
                  await chat.select(workspace, thread: thread.slug);
                } else {
                  await chat.open(thread.slug);
                }
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Sizes.cardRow),
                child: Row(
                  spacing: 8,
                  children: [
                    Flexible(
                      child: Text(
                        thread.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.sans(
                          16,
                          weight: FontWeight.w500,
                          color: t.ink,
                        ),
                      ),
                    ),
                    if (pinned)
                      AppIcon('pin', size: IconSize.xs, color: t.muted),
                    if (ready) const ReadyDot(gap: false),
                  ],
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
