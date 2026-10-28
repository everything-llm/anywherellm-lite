import 'package:flutter/material.dart';

import '../core/server_models.dart';
import 'app_scope.dart';
import 'home.dart';
import 'icons.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/buttons.dart';
import 'widgets/list_row.dart';

/// The chats as a sidebar beside everything on a wide window, in place of the shelf: the open
/// workspace's name, which opens the Workspaces sheet, with Workspace settings and New chat
/// beside it; the search; a row for the workspace's Documents; then the workspace's chats under
/// Chats, and Settings at its foot. The row of what shows is marked as chosen.
class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Search chats');

  /// What the search holds, trimmed: it changes only with the words, not with the cursor.
  final _query = ValueNotifier('');

  /// Whether the search holds anything, for its Clear button.
  final _typed = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      _query.value = _search.text.trim();
      _typed.value = _search.text.isNotEmpty;
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _query.dispose();
    _typed.dispose();
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
      label: 'Chats and pages',
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.ground,
          border: Border(right: BorderSide(color: t.line)),
        ),
        child: SafeArea(
          right: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 12, 8),
                child: WorkspaceBar(dense: true),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: ListenableBuilder(
                  listenable: _typed,
                  builder: (context, _) =>
                      ChatSearch(_search, focus: _searchFocus, dense: true),
                ),
              ),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: _query,
                  builder: (context, query, _) => query.isNotEmpty
                      ? ListenableBuilder(
                          listenable: Listenable.merge([chat, scope.prefs]),
                          builder: (context, _) => ListView(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                            children: foundChats(context, query),
                          ),
                        )
                      : CustomScrollView(
                          slivers: [
                            // The pages and the chats each rebuild on what they show.
                            ListenableBuilder(
                              listenable: Listenable.merge([chat, shell]),
                              builder: (context, _) => SliverPadding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                sliver: SliverList.list(
                                  children: _pages(context),
                                ),
                              ),
                            ),
                            ListenableBuilder(
                              listenable: Listenable.merge([
                                chat,
                                shell,
                                scope.prefs,
                              ]),
                              builder: (context, _) =>
                                  switch (chat.activeSlug) {
                                    final slug? => SliverMainAxisGroup(
                                      slivers: [
                                        SliverToBoxAdapter(
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              20,
                                              16,
                                              20,
                                              6,
                                            ),
                                            child: Semantics(
                                              header: true,
                                              child: Text(
                                                'Chats',
                                                style: Type.caption(t.ink),
                                              ),
                                            ),
                                          ),
                                        ),
                                        SliverPadding(
                                          padding: const EdgeInsets.fromLTRB(
                                            8,
                                            0,
                                            8,
                                            8,
                                          ),
                                          sliver: _chats(context, slug),
                                        ),
                                      ],
                                    ),
                                    null => const SliverToBoxAdapter(),
                                  },
                            ),
                          ],
                        ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.line)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: ListenableBuilder(
                    listenable: shell,
                    builder: (context, _) => ListRow(
                      icon: 'gear',
                      title: 'Settings',
                      selected: shell.settingsOpen,
                      onTap: shell.openSettings,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A row for each page beside the chats: the workspace's Documents.
  List<Widget> _pages(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    bool showing(Pane pane) => shell.pane == pane && !shell.settingsOpen;
    final docs = switch (scope.chat.activeSlug) {
      final slug? => scope.chat.docCounts[slug],
      null => null,
    };
    return [
      if (scope.chat.active != null)
        ListRow(
          icon: 'doc',
          title: 'Documents',
          note: docs?.toString(),
          heard: docs == null ? 'Documents' : 'Documents, $docs',
          selected: showing(Pane.documents),
          onTap: () => shell.openPane(Pane.documents),
        ),
    ];
  }

  /// The open workspace's chats, in the shelf's order: the pinned ones, then the ones this
  /// device used last, then the rest.
  Widget _chats(BuildContext context, String slug) {
    final rows = chatsInOrder(AppScope.of(context), slug);
    if (rows.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Text(
            'No chats yet.',
            style: Type.body(Tokens.of(context).muted),
          ),
        ),
      );
    }
    return SliverList.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, i) => _SidebarChat(
        rows[i].$1,
        key: ValueKey(rows[i].$1.slug),
        workspace: slug,
        pinned: rows[i].$2,
      ),
    );
  }
}

/// A chat in the sidebar: its name, after it its pin and whether its answer is ready, and a More
/// button that opens its sheet. It is marked as chosen while it shows in the chat.
class _SidebarChat extends StatelessWidget {
  const _SidebarChat(
    this.thread, {
    super.key,
    required this.workspace,
    required this.pinned,
  });

  final Thread thread;
  final String workspace;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final t = Tokens.of(context);
    final ready = scope.chat.isReady(thread.slug);
    final shown =
        shell.pane == Pane.chats &&
        !shell.settingsOpen &&
        scope.chat.thread?.slug == thread.slug;
    return ListRow(
      title: thread.name,
      heard: chatHeard(thread, pinned: pinned, ready: ready),
      selected: shown,
      badges: chatMarks(t, pinned: pinned, ready: ready),
      onTap: () => openThread(scope, workspace, thread),
      trailing: IconBtn(
        'more',
        tooltip: 'Rename, pin or delete ${thread.name}',
        box: 48,
        size: IconSize.small,
        onPressed: () => shell.openChatSheet(thread),
      ),
    );
  }
}
