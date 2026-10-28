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
import 'widgets/basics.dart';
import 'widgets/buttons.dart';
import 'widgets/fields.dart';
import 'widgets/min_height.dart';
import 'widgets/phone_page.dart';
import 'widgets/tappable.dart';
import 'workspace_switcher.dart';

/// The chats list, drawn in the shelf: the open workspace's name as its title, which opens the Workspaces sheet,
/// with Workspace settings and New chat beside it; the search; then the
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
              child: const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 16, 0),
                child: Center(child: WorkspaceBar()),
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
                              child: ChatSearch(_search, focus: _searchFocus),
                            ),
                            if (query.isNotEmpty)
                              SliverToBoxAdapter(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: foundChats(context, query),
                                ),
                              )
                            else ...[
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
    final rows = chatsInOrder(AppScope.of(context), slug);
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
}

/// [slug]'s chats in the order a list of them shows them, each with whether it is pinned: the
/// pinned ones, then the ones this device used last, then the rest.
List<(Thread, bool)> chatsInOrder(AppScope scope, String slug) => inListOrder(
  groupChats(
    scope.chat.threadsOf(slug),
    scope.prefs.pinnedIn(slug),
    scope.prefs.recentIn(slug),
  ),
);

/// What a screen reader hears for a chat in a list: its name, whether it is [pinned], and
/// whether its answer is [ready].
String chatHeard(Thread thread, {required bool pinned, required bool ready}) =>
    [thread.name, if (pinned) 'pinned', if (ready) 'answer ready'].join(', ');

/// The marks after a chat's name in a list: its pin, and the dot of an answer [ready].
List<Widget> chatMarks(Tokens t, {required bool pinned, required bool ready}) =>
    [
      if (pinned) AppIcon('pin', size: IconSize.xs, color: t.muted),
      if (ready) const ReadyMark(),
    ];

/// The open workspace's name, which opens the Workspaces sheet, with Workspace settings and New
/// chat beside it, as the shelf and, [dense], the sidebar head their chats.
class WorkspaceBar extends StatelessWidget {
  const WorkspaceBar({super.key, this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final box = dense ? 44.0 : 48.0;
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) => Row(
        spacing: 8,
        children: [
          Expanded(child: WorkspaceSwitcher(size: dense ? 20 : 26)),
          if (chat.active != null) ...[
            IconBtn(
              'settings',
              tooltip: 'Workspace settings',
              box: box,
              filled: true,
              onPressed: () => scope.shell.openPane(Pane.files),
            ),
            IconBtn(
              'plus',
              tooltip: 'New chat',
              box: box,
              filled: true,
              onPressed: () {
                chat.newChat();
                scope.shell.openChat();
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// What [query] finds: each workspace whose name or a chat of which matches, in a card with
/// its matching chats under it.
List<Widget> foundChats(BuildContext context, String query) {
  final scope = AppScope.of(context);
  final chat = scope.chat;
  final found = findChats(query, chat.orderedWorkspaces, chat.threadsOf);
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
            pinned: scope.prefs.pinnedIn(workspace.slug).contains(thread.slug),
          ),
      ]),
    ],
  ];
}

/// Opens [thread] of [workspace] in the chat, opening the workspace first when another is open,
/// with nothing over the chat.
Future<void> openThread(AppScope scope, String workspace, Thread thread) async {
  scope.shell.openChat();
  if (scope.chat.activeSlug != workspace) {
    await scope.chat.select(workspace, thread: thread.slug);
  } else {
    await scope.chat.open(thread.slug);
  }
}

/// The search: a field on the tile inside a [Tokens.lineStrong] edge, with the [FocusRing]
/// round the text while it has the focus; [dense], as the sidebar sets it, it is a control's
/// height with smaller corners.
class ChatSearch extends StatelessWidget {
  const ChatSearch(
    this.controller, {
    super.key,
    required this.focus,
    this.dense = false,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final searching = controller.text.isNotEmpty;
    return Container(
      // Its edge sits outside the field's height, as the boards draw it.
      constraints: BoxConstraints(
        minHeight: dense ? AppButton.height : Sizes.field + 2,
      ),
      padding: EdgeInsets.only(
        left: dense ? 12 : 16,
        right: searching ? 4 : (dense ? 12 : 16),
      ),
      decoration: BoxDecoration(
        color: t.tile,
        borderRadius: BorderRadius.circular(
          dense ? Sizes.small : Sizes.control,
        ),
        border: Border.all(color: t.lineStrong),
      ),
      child: Row(
        spacing: 10,
        children: [
          AppIcon('search', size: IconSize.small, color: t.muted),
          Expanded(
            child: FocusRing(
              focus: focus,
              child: FieldName(
                label: 'Search workspaces and chats',
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  autocorrect: false,
                  style: Type.body(t.ink),
                  cursorColor: t.accent,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Search chats',
                    hintStyle: Type.body(t.muted),
                  ),
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
      end: null,
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
              label: chatHeard(thread, pinned: pinned, ready: ready),
              onTap: () => openThread(scope, workspace, thread),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Sizes.cardRow),
                child: Row(
                  spacing: 8,
                  children: [
                    Flexible(child: Text(thread.name, style: Type.body(t.ink))),
                    ...chatMarks(t, pinned: pinned, ready: ready),
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
