import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/prefs.dart';
import '../../core/shortcuts.dart';
import '../app_scope.dart';
import '../state/prefs_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/phone_page.dart';
import '../widgets/segmented.dart';
import '../widgets/sheet.dart';
import '../widgets/window_insets.dart';
import 'rows.dart';

/// The Shortcuts page: the built-in shortcuts, then the person's own, each of which opens its
/// editor in a sheet, and New shortcut. Delete shortcut there takes one out at once, and a
/// toast floating at the page's foot offers Undo until it is closed, another is saved or the
/// page closes.
class ShortcutsPage extends StatefulWidget {
  const ShortcutsPage({super.key});

  @override
  State<ShortcutsPage> createState() => _ShortcutsPageState();
}

class _ShortcutsPageState extends State<ShortcutsPage> {
  PromptShortcut? _editing;
  bool _creating = false;

  /// The shortcut Delete shortcut just took out, and where it was among the person's own,
  /// while Undo can put it back.
  ({PromptShortcut shortcut, int at})? _deleted;

  void _close() => setState(() {
    _editing = null;
    _creating = false;
  });

  /// Takes [shortcut] out at once, closing its editor, with Undo to put it back.
  void _delete(PromptShortcut shortcut) {
    final prefs = AppScope.of(context).prefs;
    final at = prefs.prefs.shortcuts.indexWhere((s) => s.id == shortcut.id);
    _close();
    setState(() => _deleted = (shortcut: shortcut, at: at));
    unawaited(prefs.deleteShortcut(shortcut.id));
  }

  void _undo() {
    final deleted = _deleted;
    if (deleted == null) return;
    setState(() => _deleted = null);
    unawaited(
      AppScope.of(context).prefs
          .restoreShortcut(deleted.shortcut, at: deleted.at),
    );
  }

  /// A built-in shortcut shows as it is; one of the person's opens its editor.
  Widget _row(PromptShortcut shortcut, {required bool editable}) => NavRow(
    icon: 'slash',
    title: shortcut.label,
    about: '/${shortcut.name} · ${shortcut.prompt}',
    aboutLines: 2,
    end: editable ? 'chevron' : null,
    heard:
        '${shortcut.label}, /${shortcut.name}${editable ? ', Edit' : ', built in'}',
    onTap: editable
        ? () => setState(() {
            _editing = shortcut;
            _creating = false;
          })
        : null,
  );

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final prefs = scope.prefs;
    // The page is const where Settings builds it, so it rebuilds only for what it listens to:
    // the shortcuts, and the workspace open, which another opened beside it changes, so a
    // shortcut for this workspace only is saved for the one on screen.
    return ListenableBuilder(
      listenable: Listenable.merge([prefs, scope.chat]),
      builder: (context, _) {
        final workspace = scope.chat.active;
        final workspaceKey = scope.chat.server == null || workspace == null
            ? null
            : Prefs.offKey(scope.chat.server!.baseUrl, workspace.slug);
        final own = {for (final item in prefs.prefs.shortcuts) item.id};
        return PopupSheet(
          open: _editing != null || _creating,
          title: _creating ? 'New shortcut' : 'Shortcut',
          onClose: _close,
          sheet: (context) => _ShortcutEditor(
            key: ValueKey((_editing?.id, _creating)),
            shortcut: _editing,
            workspaceName: workspace?.name,
            workspaceKey: workspaceKey,
            nameAvailable: (name) =>
                prefs.shortcutNameAvailable(name, exceptId: _editing?.id),
            onSave: (shortcut) async {
              // A name saved now may be the one the deleted shortcut answered to.
              setState(() => _deleted = null);
              await prefs.saveShortcut(shortcut);
              if (mounted) _close();
            },
            onDelete: switch (_editing) {
              final editing? => () => _delete(editing),
              null => null,
            },
            onClose: _close,
          ),
          child: OverlayWhile(
            open: _deleted != null,
            overlay: _toast,
            child: _list(prefs, own, workspaceKey),
          ),
        );
      },
    );
  }

  /// Deleted and the shortcut's name, with Undo and Close, floating over the foot of the window.
  Widget _toast(BuildContext context) {
    final deleted = _deleted;
    if (deleted == null) return const SizedBox.shrink();
    final bars = WindowInsets.of(context);
    return Positioned(
      left: 20 + bars.left,
      right: 20 + bars.right,
      bottom: 24 + bars.bottom,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: UndoBar(
            'Deleted ${deleted.shortcut.label}',
            onUndo: _undo,
            onClose: () => setState(() => _deleted = null),
            floating: true,
          ),
        ),
      ),
    );
  }

  Widget _list(PrefsController prefs, Set<String> own, String? workspaceKey) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          const PageNote(
            'Type / in a message, or tap + beside it. A shortcut sends a prompt for you.',
          ),
          AppButton(
            'New shortcut',
            leading: 'plus',
            onPressed: () => setState(() {
              _editing = null;
              _creating = true;
            }),
          ),
          FieldCard([
            for (final shortcut in [
              ...builtInPromptShortcuts,
              ...prefs.prefs.shortcuts,
            ])
              _row(
                shortcut,
                editable:
                    own.contains(shortcut.id) &&
                    shortcut.appliesTo(workspaceKey),
              ),
          ]),
          if (prefs.problem case final problem?)
            HelpText('${problem.title}. ${problem.text}', status: true),
        ],
      );
}

/// A shortcut's editor: its name, what is typed after / to use it, its prompt, each with the
/// room under it for what is wrong with it, whether it asks for a detail first, where it shows,
/// and what it sends; then Delete shortcut for one of the person's own, and Save, which checks
/// the fields and says under each what is wrong rather than saving. A name another shortcut
/// answers to is said as it is typed.
class _ShortcutEditor extends StatefulWidget {
  const _ShortcutEditor({
    super.key,
    required this.shortcut,
    required this.workspaceName,
    required this.workspaceKey,
    required this.nameAvailable,
    required this.onSave,
    required this.onDelete,
    required this.onClose,
  });

  final PromptShortcut? shortcut;
  final String? workspaceName;
  final String? workspaceKey;
  final bool Function(String) nameAvailable;
  final ValueChanged<PromptShortcut> onSave;
  final VoidCallback? onDelete;
  final VoidCallback onClose;

  @override
  State<_ShortcutEditor> createState() => _ShortcutEditorState();
}

class _ShortcutEditorState extends State<_ShortcutEditor> {
  late final _label = TextEditingController(text: widget.shortcut?.label ?? '');
  late final _name = TextEditingController(text: widget.shortcut?.name ?? '');
  late final _prompt = TextEditingController(
    text: widget.shortcut?.prompt ?? '',
  );
  late bool _requiresDetail = widget.shortcut?.requiresDetail ?? false;
  late bool _allWorkspaces =
      widget.workspaceKey == null || widget.shortcut?.workspaceKey == null;
  late final String _id =
      widget.shortcut?.id ?? DateTime.now().microsecondsSinceEpoch.toString();

  /// Whether Save was pressed, after which each field says what is wrong with it.
  bool _checked = false;

  @override
  void dispose() {
    _label.dispose();
    _name.dispose();
    _prompt.dispose();
    super.dispose();
  }

  /// What is wrong with the name, once Save was pressed.
  String? get _labelError {
    final label = _label.text.trim();
    if (!_checked) return null;
    if (label.isEmpty) return 'Give it a name.';
    if (label.length > 30) return 'Keep the name to 30 characters or fewer.';
    return null;
  }

  /// What is wrong with what is typed after /: one another shortcut answers to as soon as it is
  /// typed, anything else once Save was pressed.
  String? get _nameError {
    final name = _name.text.trim();
    if (validShortcutName(name)) {
      return widget.nameAvailable(name)
          ? null
          : 'Another shortcut already uses that name.';
    }
    if (!_checked) return null;
    return name.isEmpty
        ? 'Choose what you type after /.'
        : 'Use lowercase letters and numbers, starting with a letter.';
  }

  /// What is wrong with the prompt, once Save was pressed.
  String? get _promptError => _checked && _prompt.text.trim().isEmpty
      ? 'Write the prompt it sends.'
      : null;

  /// Saves [value] when every field holds, and otherwise says under each what is wrong.
  void _submit(PromptShortcut value) {
    setState(() => _checked = true);
    if (_labelError == null && _nameError == null && _promptError == null) {
      widget.onSave(value);
    }
  }

  PromptShortcut _value() => PromptShortcut(
    id: _id,
    name: _name.text.trim(),
    label: _label.text.trim(),
    prompt: _prompt.text.trim(),
    workspaceKey: _allWorkspaces ? null : widget.workspaceKey,
    requiresDetail: _requiresDetail,
    detailHint: 'Add a detail',
  );

  @override
  Widget build(BuildContext context) {
    final workspaceName = widget.workspaceName ?? 'this workspace';
    return ListenableBuilder(
      listenable: Listenable.merge([_label, _name, _prompt]),
      builder: (context, _) {
        final value = _value();
        final example = value.expand(
          value.prompt.contains('{text}') || value.requiresDetail
              ? 'French'
              : '',
        );
        final labelError = _labelError;
        final nameError = _nameError;
        final promptError = _promptError;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              NamedControl(
                'Name',
                _Checked(
                  AppField(
                    controller: _label,
                    label: 'Name',
                    hint: 'Make it formal',
                    invalid: labelError != null,
                  ),
                  // No rule to show, so the room is taken only by what is wrong.
                  message: labelError == null
                      ? null
                      : FieldMessage(error: labelError),
                ),
              ),
              NamedControl(
                'Typed as',
                _Checked(
                  AppField(
                    controller: _name,
                    label: 'Shortcut name',
                    hint: 'formal',
                    invalid: nameError != null,
                  ),
                  message: FieldMessage(
                    error: nameError,
                    help: 'Lowercase letters and numbers, not used by another shortcut.',
                  ),
                ),
              ),
              NamedControl(
                'Prompt',
                _Checked(
                  AppField(
                    controller: _prompt,
                    label: 'Prompt',
                    hint: 'Rewrite your last answer in a formal tone.',
                    maxLines: 4,
                    invalid: promptError != null,
                  ),
                  message: FieldMessage(
                    error: promptError,
                    help:
                        'Write it as you would say it. Use {text} where a detail you type '
                        'should go.',
                  ),
                ),
              ),
              FieldCard([
                FieldRow.toggle(
                  label: 'Ask for a detail first',
                  help: 'Waits until you type one, such as a language.',
                  value: _requiresDetail,
                  onChanged: (on) => setState(() => _requiresDetail = on),
                ),
              ]),
              NamedControl(
                'Shown in',
                Segmented<bool>(
                  options: [
                    (true, 'Every workspace'),
                    (false, 'Only $workspaceName'),
                  ],
                  value: _allWorkspaces,
                  onChanged: widget.workspaceKey == null
                      ? null
                      : (all) => setState(() => _allWorkspaces = all),
                ),
              ),
              const CardCaption('Example of what is sent'),
              // A well on the ground, as a preview rather than a card.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Tokens.of(context).ground,
                  border: Border.all(color: Tokens.of(context).line),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  example.isEmpty ? 'Write a prompt to preview it.' : example,
                  style: Type.body(Tokens.of(context).ink),
                ),
              ),
              ActionRow(even: true, [
                if (widget.onDelete case final delete?)
                  AppButton('Delete shortcut', danger: true, onPressed: delete),
                AppButton(
                  'Save',
                  primary: true,
                  compact: widget.onDelete != null,
                  onPressed: () => _submit(value),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }
}

/// A field with [message], the room under it for what is wrong with it, 6 under it.
class _Checked extends StatelessWidget {
  const _Checked(this.field, {required this.message});

  final Widget field;
  final Widget? message;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 6,
    children: [field, ?message],
  );
}
