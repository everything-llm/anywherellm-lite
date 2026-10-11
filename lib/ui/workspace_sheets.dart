import 'dart:async';

import 'package:flutter/material.dart';

import '../core/copy.dart';
import 'app_scope.dart';
import 'settings/rows.dart';
import 'state/shell_controller.dart';
import 'widgets/buttons.dart';
import 'widgets/fields.dart';
import 'widgets/sheet.dart';

/// A phone's sheet about the open workspace, over the window: a new workspace's name, the open
/// one's new name, or whether to delete it, with Keep and Delete side by side.
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

  @override
  void dispose() {
    _name.dispose();
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
      unawaited(chat.createWorkspace(typed));
      _scope.shell.closeSide();
    } else if (active != null && typed != active.name) {
      unawaited(chat.renameWorkspace(active.slug, typed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.kind) {
      WorkspaceSheet.create => 'New workspace',
      WorkspaceSheet.rename => 'Rename workspace',
      WorkspaceSheet.delete => 'Delete workspace',
    };
    // A name's field takes the focus itself.
    return ModalSheet(
      title: title,
      onClose: _close,
      autofocus: widget.kind == WorkspaceSheet.delete,
      child: widget.kind == WorkspaceSheet.delete
          ? _delete(context)
          : _naming(context),
    );
  }

  Widget _naming(BuildContext context) {
    return Column(
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
            onSubmitted: (_) => _named(),
          ),
        ),
        ActionRow(even: true, [
          AppButton(
            widget.kind == WorkspaceSheet.create ? 'Create' : 'Save',
            primary: true,
            onPressed: _named,
          ),
        ]),
      ],
    );
  }

  Widget _delete(BuildContext context) {
    final chat = _scope.chat;
    final active = chat.active;
    final chats = plural(
      chat.threadsOf(active?.slug ?? '').length,
      'chat',
      'chats',
    );
    return SheetQuestion(
      'Delete ${active?.name} and its $chats? Its documents stay in the library.',
      onKeep: _close,
      onDelete: active == null || chat.answeringIn(active.slug)
          ? null
          : () {
              _close();
              unawaited(chat.deleteWorkspace(active.slug));
            },
    );
  }
}
