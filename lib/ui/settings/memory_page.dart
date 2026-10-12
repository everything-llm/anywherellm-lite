import 'package:flutter/material.dart';

import '../../core/memory.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../state/memory_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../state/shell_controller.dart';
import '../widgets/phone_page.dart';
import '../widgets/radio_card.dart';
import '../widgets/sheet.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';
import '../widgets/tappable.dart';
import 'rows.dart';

/// The Memory page's sheet for one saved memory, or a new one, in the shell's popup, so Back
/// closes it: [key] is `g:<id>` or `w:<id>` for a saved memory, `g:new` or `w:new` for a new
/// one.
class MemorySheet {
  const MemorySheet(this.key);

  final String key;

  @override
  bool operator ==(Object other) => other is MemorySheet && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// What chats are shown about the person, for one workspace, picked at the top in a sheet:
/// AnythingLLM's saved memories, with its switches, those for every workspace and the
/// workspace's own. A row opens a sheet to change or delete it.
class MemoryPage extends StatelessWidget {
  const MemoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    return ListenableBuilder(
      listenable: Listenable.merge([scope.memory, scope.chat, shell.popup]),
      builder: (context, _) {
        final memory = scope.memory;
        memory.want();
        final slug = memory.slug;
        final names = {for (final w in scope.chat.workspaces) w.slug: w.name};
        final name = names[slug] ?? slug ?? 'this workspace';
        final open = switch (shell.popup.value) {
          final MemorySheet sheet => sheet,
          _ => null,
        };
        return PopupSheet(
          open: open != null,
          onClose: shell.closePopup,
          title: open?.key.endsWith(':new') ?? false
              ? 'New memory'
              : 'Saved memory',
          sheet: (context) => _SavedEditor(
            key: ValueKey(open?.key),
            memory: _memoryOf(memory, open?.key),
            global: open?.key.startsWith('g:') ?? true,
            name: name,
            onDone: shell.closePopup,
          ),
          child: PopupSheet(
            open: shell.popup.value == Popup.memoryWorkspace,
            onClose: shell.closePopup,
            title: 'Workspace',
            sheet: (context) => _WorkspaceChoice(names, slug),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FieldCard([
                  NavRow(
                    icon: 'grid',
                    title: 'Workspace',
                    about: names[slug] ?? 'No workspace',
                    heard:
                        'Workspace: ${names[slug] ?? 'none'}. Choose another',
                    onTap: memory.busy
                        ? null
                        : () => shell.togglePopup(Popup.memoryWorkspace),
                  ),
                ]),
                ..._saved(context, memory, name),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The saved memory [key] names, or null for a new one.
  static SavedMemory? _memoryOf(MemoryController memory, String? key) {
    if (key == null || key.endsWith(':new')) return null;
    final saved = memory.saved;
    final id = int.tryParse(key.substring(2));
    return [
      ...?saved?.global,
      ...?saved?.workspace,
    ].where((m) => m.id == id).firstOrNull;
  }

  List<Widget> _saved(
    BuildContext context,
    MemoryController memory,
    String name,
  ) {
    final switches = memory.switches;
    final saved = memory.saved;
    return [
      if (memory.savedProblem case final problem?) ...[
        const SizedBox(height: 20),
        AlertBox(AlertKind.bad, problem.title, text: problem.text),
      ],
      if (switches == null)
        if (memory.loading) ...[
          const SizedBox(height: 20),
          const HelpText('Loading…', status: true),
        ] else
          ...[]
      else ...[
        CardHeading('Saved memories'),
        FieldCard([
          FieldRow(
            label: 'Saved memories',
            help: 'Every chat is shown them',
            small: true,
            control: AppSwitch(
              value: switches.enabled,
              label: 'Saved memories',
              onChanged: memory.busy
                  ? null
                  : (on) => memory.setSwitches(enabled: on),
            ),
          ),
          if (switches.enabled)
            FieldRow(
              label: 'Learn from chats',
              help: 'AnythingLLM saves what it notices',
              small: true,
              control: AppSwitch(
                value: switches.learn,
                label: 'Learn from chats',
                onChanged: memory.busy
                    ? null
                    : (on) => memory.setSwitches(learn: on),
              ),
            ),
        ]),
        if (!switches.enabled) ...[
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: FieldCard.inset),
            child: PageNote(
              'Off: chats are shown no saved memories, and none are saved.',
            ),
          ),
        ] else if (saved != null) ...[
          CardHeading(
            'Every workspace · ${saved.global.length} of $globalMemoryLimit',
          ),
          _savedList(context, saved.global, global: true),
          CardHeading(
            'Only $name · ${saved.workspace.length} of $workspaceMemoryLimit',
          ),
          _savedList(context, saved.workspace, global: false),
        ],
      ],
    ];
  }

  Widget _savedList(
    BuildContext context,
    List<SavedMemory> list, {
    required bool global,
  }) {
    final shell = AppScope.of(context).shell;
    final scope = global ? 'g' : 'w';
    final limit = global ? globalMemoryLimit : workspaceMemoryLimit;
    return FieldCard([
      for (final m in list)
        _Item(
          key: ValueKey('$scope:${m.id}'),
          text: m.text,
          heard: '${m.text} Change or delete',
          onTap: () => shell.togglePopup(MemorySheet('$scope:${m.id}')),
        ),
      if (list.length >= limit)
        CardNote('All $limit in use. Delete one to add another.')
      else
        _Item(
          key: ValueKey('$scope:new'),
          add: true,
          text: 'Add a memory',
          onTap: () => shell.togglePopup(MemorySheet('$scope:new')),
        ),
    ]);
  }
}

/// The Workspace sheet: each workspace, the one shown checked, then what the choice changes.
class _WorkspaceChoice extends StatelessWidget {
  const _WorkspaceChoice(this.names, this.slug);

  final Map<String, String> names;
  final String? slug;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        FieldCard(inSheet: true, [
          for (final MapEntry(key: each, value: name) in names.entries)
            CardRow(
              name,
              checked: each == slug,
              onTap: () {
                scope.shell.closePopup();
                scope.memory.show(each);
              },
            ),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Memories for every workspace show whichever you pick.',
            style: Type.note(t.muted),
          ),
        ),
      ],
    );
  }
}

/// A row of a memory's card: its [text], wrapped, which a tap opens in a sheet. An [add] row
/// is a plus and its words in the accent.
class _Item extends StatelessWidget {
  const _Item({
    super.key,
    required this.text,
    required this.onTap,
    this.heard,
    this.add = false,
  });

  final String text;
  final String? heard;
  final VoidCallback onTap;
  final bool add;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: heard ?? text,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(
          horizontal: FieldCard.inset,
          vertical: 12,
        ),
        child: Row(
          spacing: 12,
          children: [
            if (add) AppIcon('plus', color: t.accent),
            Expanded(
              child: Text(
                text,
                style: Type.sans(
                  16,
                  weight: add ? FontWeight.w600 : FontWeight.w500,
                  color: add ? t.accent : t.ink,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A saved memory's text and where it shows, to add or change it, with Delete for one that is
/// saved.
class _SavedEditor extends StatefulWidget {
  const _SavedEditor({
    super.key,
    this.memory,
    required this.global,
    required this.name,
    required this.onDone,
  });

  /// The memory changed, or null for a new one.
  final SavedMemory? memory;

  /// Whether it shows in every workspace, as it starts.
  final bool global;

  /// The workspace's name.
  final String name;
  final VoidCallback onDone;

  @override
  State<_SavedEditor> createState() => _SavedEditorState();
}

class _SavedEditorState extends State<_SavedEditor> {
  late final _text = TextEditingController(text: widget.memory?.text ?? '');
  late bool _global = widget.global;
  bool _asking = false;
  String? _problem;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final memory = AppScope.of(context).memory;
    final text = _text.text.trim();
    final problem = _problemWith(text, memory);
    setState(() => _problem = problem);
    if (problem != null) return;
    final done = switch (widget.memory) {
      final m? => await memory.edit(m, text, global: _global),
      null => await memory.add(text, global: _global),
    };
    if (done && mounted) widget.onDone();
  }

  String? _problemWith(String text, MemoryController memory) {
    if (text.isEmpty) return 'Write the memory first.';
    if (text.length > memoryTextMax) {
      return 'Keep it to $memoryTextMax characters.';
    }
    final saved = memory.saved;
    final moving = widget.memory == null || _global != widget.memory!.global;
    if (saved != null && moving) {
      if (_global && saved.global.length >= globalMemoryLimit) {
        return 'Every workspace has $globalMemoryLimit already. Delete one first.';
      }
      if (!_global && saved.workspace.length >= workspaceMemoryLimit) {
        return '${widget.name} has $workspaceMemoryLimit already. Delete one first.';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final memory = AppScope.of(context).memory;
    final t = Tokens.of(context);
    final existing = widget.memory;
    final saved = memory.saved;
    // A list that is full takes no memory from the other, as the design canvas draws it.
    bool full(bool global) =>
        saved != null &&
        (existing == null || existing.global != global) &&
        (global
            ? saved.global.length >= globalMemoryLimit
            : saved.workspace.length >= workspaceMemoryLimit);
    RadioCard choice(bool global, String title, int limit) => RadioCard(
      title: title,
      about: full(global) ? 'Full' : '$limit at most',
      selected: _global == global,
      onTap: () => setState(() => _global = global),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        AppField(
          controller: _text,
          label: 'Memory',
          hint: 'One short fact, such as: Prefers metric units.',
          maxLines: 4,
          autofocus: existing == null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SectionLabel('Shown in', header: false),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            choice(true, 'Every workspace', globalMemoryLimit),
            choice(false, 'Only ${widget.name}', workspaceMemoryLimit),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Every chat there is shown it, word for word.',
            style: Type.note(t.muted),
          ),
        ),
        if (_problem case final problem?)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(problem, style: Type.sans(13.5, color: t.badfg)),
          ),
        if (_asking && existing != null)
          SheetQuestion(
            'Delete this memory? Chats are no longer shown it.',
            onKeep: () => setState(() => _asking = false),
            onDelete: memory.busy
                ? null
                : () async {
                    if (await memory.delete(existing) && mounted) {
                      widget.onDone();
                    }
                  },
          )
        else
          ActionRow(even: true, [
            if (existing != null)
              AppButton(
                'Delete',
                danger: true,
                onPressed: memory.busy
                    ? null
                    : () => setState(() => _asking = true),
              ),
            AppButton(
              existing == null ? 'Add' : 'Save',
              primary: true,
              onPressed: memory.busy ? null : _save,
            ),
          ]),
      ],
    );
  }
}
