import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/chat_groups.dart';
import '../core/find.dart';
import '../core/server_models.dart';
import 'app_scope.dart';
import 'icons.dart';
import 'layout.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/fields.dart';
import 'widgets/tappable.dart';

/// A workspace, or one of its chats, in the switcher's list.
typedef _Entry = ({Workspace workspace, Thread? thread});

/// Ctrl+K: a box over the window to go to any workspace or chat by typing part of its name.
/// With nothing typed it lists each workspace with its pinned and recent chats; typed, it lists
/// what the sidebar's search finds. Up and Down move, Enter opens, Esc closes.
class QuickSwitcher extends StatefulWidget {
  const QuickSwitcher({super.key});

  @override
  State<QuickSwitcher> createState() => _QuickSwitcherState();
}

class _QuickSwitcherState extends State<QuickSwitcher> {
  static const _row = 40.0;

  final _query = TextEditingController();
  final _focus = FocusNode(debugLabel: 'Quick switcher');
  final _scroll = ScrollController();

  /// The row the person moved to, or null for the first chat found (the first row when nothing
  /// is typed or only workspaces match).
  int? _picked;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() => _picked = null));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<_Entry> _entries(AppScope scope) {
    final chat = scope.chat;
    final ordered = scope.prefs.prefs.inOrder(chat.workspaces, (w) => w.slug);
    final query = _query.text.trim();
    if (query.isNotEmpty) {
      return [
        for (final (workspace, threads) in findChats(
          query,
          ordered,
          chat.threadsOf,
        )) ...[
          (workspace: workspace, thread: null),
          for (final thread in threads) (workspace: workspace, thread: thread),
        ],
      ];
    }
    return [
      for (final workspace in ordered) ...[
        (workspace: workspace, thread: null),
        ...() {
          final groups = groupChats(
            chat.threadsOf(workspace.slug),
            scope.prefs.pinnedIn(workspace.slug),
            scope.prefs.recentIn(workspace.slug),
          );
          return [
            for (final thread in [...groups.pinned, ...groups.recent])
              (workspace: workspace, thread: thread),
          ];
        }(),
      ],
    ];
  }

  int _selected(List<_Entry> entries) {
    if (entries.isEmpty) return 0;
    if (_picked case final picked?) return picked.clamp(0, entries.length - 1);
    if (_query.text.trim().isEmpty) return 0;
    final chat = entries.indexWhere((e) => e.thread != null);
    return chat < 0 ? 0 : chat;
  }

  void _move(int by, List<_Entry> entries) {
    if (entries.isEmpty) return;
    final index = (_selected(entries) + by).clamp(0, entries.length - 1);
    setState(() => _picked = index);
    if (!_scroll.hasClients) return;
    final top = index * _row;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + _row > _scroll.offset + view) {
      _scroll.jumpTo(top + _row - view);
    }
  }

  /// Goes to [entry] and puts the switcher away.
  void _open(AppScope scope, _Entry entry) {
    final chat = scope.chat;
    final slug = entry.workspace.slug;
    scope.shell
      ..closePopup(Popup.switcher)
      ..closeSide()
      ..showPane(Pane.chats);
    switch (entry.thread) {
      case null:
        if (chat.activeSlug != slug) chat.select(slug);
      case final thread when chat.activeSlug != slug:
        chat.select(slug, thread: thread.slug);
      case final thread:
        chat.open(thread.slug);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final size = MediaQuery.sizeOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.chat, scope.prefs, _query]),
      builder: (context, _) {
        final entries = _entries(scope);
        final index = _selected(entries);
        return Semantics(
          container: true,
          label: 'Go to a workspace or chat',
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _move(1, entries),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _move(-1, entries),
            },
            child: Container(
              width: (size.width - 32).clamp(0, 560),
              constraints: BoxConstraints(maxHeight: size.height * 0.6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.panel,
                borderRadius: BorderRadius.circular(Sizes.card),
                border: Border.all(color: t.line),
                boxShadow: [
                  BoxShadow(
                    color: t.shadow,
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppField(
                    controller: _query,
                    focusNode: _focus,
                    label: 'Go to a workspace or chat',
                    hint: 'Go to a workspace or chat',
                    icon: 'search',
                    onSubmitted: (_) {
                      if (entries.isNotEmpty) {
                        _open(scope, entries[index]);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  if (entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _query.text.trim().isEmpty
                            ? 'No workspaces yet.'
                            : 'Nothing matches "${_query.text.trim()}".',
                        style: Type.sans(13.5, color: t.muted),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        itemExtent: _row,
                        itemCount: entries.length,
                        itemBuilder: (context, i) => _Row(
                          entries[i],
                          selected: i == index,
                          onTap: () => _open(scope, entries[i]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.entry, {required this.selected, required this.onTap});

  final _Entry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final chat = AppScope.of(context).chat;
    final thread = entry.thread;
    final slug = entry.workspace.slug;
    final current = thread == null
        ? chat.activeSlug == slug
        : chat.activeSlug == slug && chat.activeThread == thread.slug;
    return Tappable(
      label: thread?.name ?? entry.workspace.name,
      selected: selected,
      onTap: onTap,
      radius: BorderRadius.circular(8),
      color: selected ? t.sel : null,
      child: Padding(
        padding: EdgeInsets.only(left: thread == null ? 10 : 36, right: 10),
        child: Row(
          children: [
            if (thread == null) ...[
              AppIcon('chat', size: IconSize.small, color: t.muted),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                thread?.name ?? entry.workspace.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.sans(
                  thread == null ? 14.5 : 14,
                  weight: current ? FontWeight.w600 : FontWeight.w400,
                  color: thread == null ? t.ink : t.ink2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
