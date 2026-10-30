import 'dart:async';

import 'package:flutter/material.dart';

import '../core/copy.dart';
import 'app_scope.dart';
import 'settings/rows.dart';
import 'state/shell_controller.dart';
import 'widgets/buttons.dart';
import 'widgets/fields.dart';
import 'widgets/sheet.dart';

/// A phone's sheet about the open workspace, over the window: a new workspace's name and
/// instructions, the open one's new name, or whether to delete it (Delete workspace?), with Keep
/// and Delete workspace side by side.
class WorkspaceSheetView extends StatefulWidget {
  const WorkspaceSheetView(this.kind, {super.key});

  final WorkspaceSheet kind;

  @override
  State<WorkspaceSheetView> createState() => _WorkspaceSheetViewState();
}

class _WorkspaceSheetViewState extends State<WorkspaceSheetView> {
  late final AppScope _scope = AppScope.of(context);
  late final _name = TextEditingController(
    text: widget.kind == WorkspaceSheet.rename
        ? _scope.chat.active?.name ?? ''
        : '',
  );

  /// A new workspace's system prompt. Left empty, the server's default applies.
  final _instructions = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _instructions.dispose();
    super.dispose();
  }

  void _close() => _scope.shell.closePopup();

  void _named() {
    final chat = _scope.chat;
    final typed = _name.text.trim();
    final active = chat.active;
    _close();
    if (typed.isEmpty) return;
    if (widget.kind == WorkspaceSheet.create) {
      unawaited(chat.createWorkspace(typed, prompt: _instructions.text));
      _scope.shell.openChat();
    } else if (active != null && typed != active.name) {
      unawaited(chat.renameWorkspace(active.slug, typed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.kind) {
      WorkspaceSheet.create => 'New workspace',
      WorkspaceSheet.rename => 'Rename workspace',
      WorkspaceSheet.delete => 'Delete workspace?',
    };
    // A name's field takes the focus itself.
    return ModalSheet(
      title: title,
      onClose: _close,
      autofocus: widget.kind == WorkspaceSheet.delete,
      child: widget.kind == WorkspaceSheet.delete ? _delete() : _naming(),
    );
  }

  Widget _naming() {
    final create = widget.kind == WorkspaceSheet.create;
    // It scrolls when the keyboard leaves it too little room.
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          NamedControl(
            'Name',
            quiet: true,
            labelled: true,
            AppField(
              controller: _name,
              label: 'Name',
              autofocus: true,
              onSubmitted: (_) => _name.text.trim().isEmpty ? null : _named(),
            ),
          ),
          if (create)
            NamedControl(
              'Instructions',
              quiet: true,
              labelled: true,
              AppField(
                controller: _instructions,
                label: 'Instructions',
                hint: 'Empty: the server\'s default system prompt applies.',
                maxLines: 8,
              ),
            ),
          // Nothing to save without a name, so the button is off rather than closing the
          // sheet and doing nothing.
          ListenableBuilder(
            listenable: _name,
            builder: (context, _) => ActionRow(even: true, [
              AppButton(
                create ? 'Create' : 'Save',
                primary: true,
                onPressed: _name.text.trim().isEmpty ? null : _named,
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _delete() {
    final chat = _scope.chat;
    final active = chat.active;
    final chats = plural(
      chat.threadsOf(active?.slug ?? '').length,
      'chat',
      'chats',
    );
    return SheetQuestion(
      'Delete ${active?.name} and its $chats? Its documents stay in the library. This '
      'can’t be undone.',
      action: 'Delete workspace',
      onKeep: _close,
      onConfirm: active == null || !chat.activeIdle
          ? null
          : () {
              _close();
              unawaited(chat.deleteWorkspace(active.slug));
            },
    );
  }
}
