import 'package:flutter/material.dart';

import '../core/copy.dart';
import '../core/server_models.dart';
import 'app_scope.dart';
import 'icons.dart';
import 'layout.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/basics.dart';
import 'widgets/brand.dart';
import 'widgets/buttons.dart';
import 'widgets/inline_input.dart';
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
      child: Container(
        width: Sizes.sidebar,
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
        decoration: BoxDecoration(
          color: t.side,
          border: Border(right: BorderSide(color: t.line)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(8, 2, 8, 16),
              child: Align(alignment: Alignment.centerLeft, child: Brand()),
            ),
            Expanded(child: _Workspaces()),
            SizedBox(height: 8),
            SidebarSettingsButton(),
          ],
        ),
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

  @override
  void dispose() {
    _name.dispose();
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

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 14, 4, 6),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.line)),
            ),
            child: Row(
              children: [
                const Expanded(child: SectionLabel('Workspaces')),
                IconBtn(
                  'plus',
                  tooltip: 'New workspace',
                  box: 24,
                  size: IconSize.xs,
                  onPressed: () => setState(() => _adding = true),
                ),
              ],
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
          Expanded(
            child: ListView(
              children: [for (final w in chat.workspaces) _WorkspaceRow(w)],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceRow extends StatelessWidget {
  const _WorkspaceRow(this.workspace);

  final Workspace workspace;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final t = Tokens.of(context);
    final active = chat.activeSlug == workspace.slug;
    final count = chat.docCounts[workspace.slug];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tappable(
          label: workspace.name,
          selected: active,
          onTap: () {
            if (!active) chat.select(workspace.slug);
          },
          radius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                NilsIcon('chat', size: IconSize.small, color: t.muted),
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
        if (active) ...[
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
                  NilsIcon('plus', size: IconSize.xs, color: t.accent),
                  const SizedBox(width: 6),
                  Text('New chat', style: Type.sans(13.5, color: t.accent)),
                ],
              ),
            ),
          ),
          for (final thread in chat.threadsOf(workspace.slug).reversed)
            _ChatRow(thread, current: chat.activeThread == thread.slug),
        ],
      ],
    );
  }
}

class _ChatRow extends StatefulWidget {
  const _ChatRow(this.thread, {required this.current});

  final Thread thread;
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
              onTap: () {
                scope.chat.open(widget.thread.slug);
                scope.shell.closeSide();
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
