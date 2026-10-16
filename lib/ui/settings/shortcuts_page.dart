import 'package:flutter/material.dart';

import '../../core/prefs.dart';
import '../../core/shortcuts.dart';
import '../app_scope.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/phone_page.dart';
import '../widgets/segmented.dart';
import '../widgets/sheet.dart';
import 'rows.dart';

class ShortcutsPage extends StatefulWidget {
  const ShortcutsPage({super.key});

  @override
  State<ShortcutsPage> createState() => _ShortcutsPageState();
}

class _ShortcutsPageState extends State<ShortcutsPage> {
  PromptShortcut? _editing;
  bool _creating = false;

  void _close() => setState(() {
    _editing = null;
    _creating = false;
  });

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
    final workspace = scope.chat.active;
    final workspaceKey = scope.chat.server == null || workspace == null
        ? null
        : Prefs.offKey(scope.chat.server!.baseUrl, workspace.slug);
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
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
              await prefs.saveShortcut(shortcut);
              if (mounted) _close();
            },
            onDelete: _editing == null
                ? null
                : () async {
                    await prefs.deleteShortcut(_editing!.id);
                    if (mounted) _close();
                  },
            onClose: _close,
          ),
          child: Column(
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
          ),
        );
      },
    );
  }
}

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
  bool _confirmDelete = false;

  @override
  void dispose() {
    _label.dispose();
    _name.dispose();
    _prompt.dispose();
    super.dispose();
  }

  bool get _valid =>
      _label.text.trim().isNotEmpty &&
      _label.text.trim().length <= 30 &&
      widget.nameAvailable(_name.text.trim()) &&
      _prompt.text.trim().isNotEmpty;

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
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              NamedControl(
                'Name',
                AppField(
                  controller: _label,
                  label: 'Name',
                  hint: 'Make it formal',
                ),
              ),
              NamedControl(
                'Typed as',
                AppField(
                  controller: _name,
                  label: 'Shortcut name',
                  hint: 'formal',
                ),
              ),
              NamedControl(
                'Prompt',
                AppField(
                  controller: _prompt,
                  label: 'Prompt',
                  hint: 'Rewrite your last answer in a formal tone.',
                  maxLines: 4,
                ),
              ),
              const CardCaption(
                'Write it as you would say it. Use {text} where a detail you type should go.',
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
              Container(
                padding: const EdgeInsets.all(14),
                decoration: cardDecoration(Tokens.of(context)),
                child: Text(
                  example.isEmpty ? 'Write a prompt to preview it.' : example,
                  style: Type.sans(
                    15,
                    color: Tokens.of(context).ink,
                    height: 1.5,
                  ),
                ),
              ),
              if (_name.text.trim().isNotEmpty &&
                  !widget.nameAvailable(_name.text.trim()))
                const HelpText('Another shortcut already uses that name.'),
              if (_confirmDelete)
                SheetQuestion(
                  'Delete ${widget.shortcut!.label}?',
                  onKeep: () => setState(() => _confirmDelete = false),
                  onDelete: widget.onDelete,
                )
              else
                ActionRow(even: true, [
                  if (widget.onDelete != null)
                    AppButton(
                      'Delete',
                      danger: true,
                      onPressed: () => setState(() => _confirmDelete = true),
                    ),
                  AppButton(
                    'Save',
                    primary: true,
                    onPressed: _valid ? () => widget.onSave(value) : null,
                  ),
                ]),
            ],
          ),
        );
      },
    );
  }
}
