import 'dart:async';

import 'package:flutter/material.dart';

import '../core/server_models.dart';
import 'app_scope.dart';
import 'settings/rows.dart';
import 'state/shell_controller.dart';
import 'widgets/fields.dart';
import 'widgets/sheet.dart';

/// A phone's sheet for one chat of the workspace on screen, over the window: its name, which
/// renames it as it is typed, Pin to the top and Delete chat, which asks first in the sheet's
/// place (Delete chat?), since the server deletes the thread for good ([ChatController.delete]).
/// Keep there goes back to the chat's sheet.
class ChatSheet extends StatefulWidget {
  const ChatSheet(this.of, {super.key});

  final ChatSheetFor of;

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  late final AppScope _scope;
  late final _name = TextEditingController(text: widget.of.thread.name);
  Timer? _wait;

  /// Whether Delete chat? shows in the sheet's place.
  bool _asking = false;

  /// How long typing pauses before the name is saved.
  static const _pause = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    _scope = AppScope.of(context);
  }

  @override
  void dispose() {
    _save();
    _name.dispose();
    super.dispose();
  }

  void _typed(String _) {
    _wait?.cancel();
    _wait = Timer(_pause, _save);
  }

  /// Saves the name typed, unless it is empty or what the chat is already called.
  void _save() {
    _wait?.cancel();
    _wait = null;
    final name = _name.text.trim();
    final now = _now;
    if (name.isEmpty || now == null || name == now.name) return;
    unawaited(_scope.chat.rename(now.slug, name));
  }

  /// The chat as the workspace on screen has it now, or null once it is gone.
  Thread? get _now => _scope.chat
      .threadsOf(_scope.chat.activeSlug ?? '')
      .where((t) => t.slug == widget.of.thread.slug)
      .firstOrNull;

  void _close() => _scope.shell.closePopup();

  @override
  Widget build(BuildContext context) {
    if (_asking) {
      return ModalSheet(
        title: 'Delete chat?',
        onClose: _close,
        child: ListenableBuilder(
          listenable: _scope.chat,
          builder: (context, _) => _delete(),
        ),
      );
    }
    return ModalSheet(title: 'Chat', onClose: _close, child: _sheet());
  }

  Widget _delete() {
    final chat = _scope.chat;
    final thread = widget.of.thread;
    final name = _now?.name ?? thread.name;
    return SheetQuestion(
      'Delete $name? Its messages go with it. This can’t be undone.',
      action: 'Delete chat',
      onKeep: () => setState(() => _asking = false),
      onConfirm: chat.isAnswering(thread.slug)
          ? null
          : () {
              _close();
              unawaited(chat.delete(thread.slug));
            },
    );
  }

  Widget _sheet() {
    final scope = _scope;
    final thread = widget.of.thread;
    final workspace = scope.chat.activeSlug ?? '';
    return ListenableBuilder(
      listenable: Listenable.merge([scope.prefs, scope.chat]),
      builder: (context, _) {
        final pinned = scope.prefs.pinnedIn(workspace).contains(thread.slug);
        final answering = scope.chat.isAnswering(thread.slug);
        return SingleChildScrollView(
          child: Column(
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
                  onChanged: _typed,
                  onSubmitted: (_) => _save(),
                ),
              ),
              FieldCard([
                FieldRow.toggle(
                  label: 'Pin to the top',
                  value: pinned,
                  onChanged: (on) => unawaited(
                    scope.prefs.setPinned(workspace, thread.slug, on: on),
                  ),
                ),
              ]),
              FieldCard([
                CardRow(
                  'Delete chat',
                  icon: 'trash',
                  tone: RowTone.danger,
                  onTap: answering
                      ? null
                      : () {
                          _save();
                          setState(() => _asking = true);
                        },
                ),
              ]),
            ],
          ),
        );
      },
    );
  }
}
