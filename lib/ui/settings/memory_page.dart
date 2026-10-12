import 'package:flutter/material.dart';

import '../../core/memory.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../state/memory_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/confirm_box.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';
import '../widgets/segmented.dart';
import '../widgets/tappable.dart';
import 'rows.dart';

/// What chats are shown about the person, for one workspace, picked at the top: AnythingLLM's
/// saved memories, with its switches, those for every workspace and the workspace's own. A row
/// opens under itself to change or delete it, one at a time.
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key});

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  /// The row open under itself: `g:<id>` or `w:<id>` for a saved memory, `g:new` or `w:new` for
  /// a new one.
  String? _open;

  void _toggle(String key) => setState(() => _open = _open == key ? null : key);

  void _close() => setState(() => _open = null);

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.memory, scope.chat]),
      builder: (context, _) {
        final memory = scope.memory;
        memory.want();
        final slug = memory.slug;
        final names = {for (final w in scope.chat.workspaces) w.slug: w.name};
        final name = names[slug] ?? slug ?? 'this workspace';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            FieldCard([
              FieldRow(
                label: 'Workspace',
                help: 'Memories for every workspace show whichever you pick.',
                control: AppSelect(
                  value: slug,
                  choices: names.keys.toList(),
                  labelOf: (s) => names[s] ?? s,
                  hint: 'No workspace',
                  onChanged: memory.busy
                      ? null
                      : (s) {
                          if (s == null) return;
                          setState(() => _open = null);
                          memory.show(s);
                        },
                ),
              ),
            ]),
            const SubHead('Saved memories'),
            const PageNote(
              'Every chat is shown them, word for word. AnythingLLM keeps '
              '$globalMemoryLimit for every workspace and $workspaceMemoryLimit for each one.',
            ),
            ..._saved(memory, name),
          ],
        );
      },
    );
  }

  List<Widget> _saved(MemoryController memory, String name) {
    final switches = memory.switches;
    final saved = memory.saved;
    return [
      if (memory.savedProblem case final problem?)
        AlertBox(AlertKind.bad, problem.title, text: problem.text),
      if (switches == null)
        if (memory.loading) const HelpText('Loading…', status: true) else ...[]
      else ...[
        FieldCard([
          FieldRow(
            label: 'Saved memories',
            help: 'Chats are shown them, and AnythingLLM keeps them.',
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
              help: 'AnythingLLM saves what it notices in chats.',
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
        if (!switches.enabled)
          const PageNote(
            'Off: chats are shown no saved memories, and none are saved.',
          )
        else if (saved != null) ...[
          SectionLabel(
            'Every workspace · ${saved.global.length} of $globalMemoryLimit',
          ),
          _savedList(saved.global, global: true, name: name),
          SectionLabel(
            'Only $name · ${saved.workspace.length} of $workspaceMemoryLimit',
          ),
          _savedList(saved.workspace, global: false, name: name),
        ],
      ],
    ];
  }

  Widget _savedList(
    List<SavedMemory> list, {
    required bool global,
    required String name,
  }) {
    final scope = global ? 'g' : 'w';
    final limit = global ? globalMemoryLimit : workspaceMemoryLimit;
    return FieldCard([
      for (final m in list)
        _Item(
          key: ValueKey('$scope:${m.id}'),
          text: m.text,
          heard: '${m.text} Change or delete',
          open: _open == '$scope:${m.id}',
          onTap: () => _toggle('$scope:${m.id}'),
          panel: _SavedEditor(
            memory: m,
            global: global,
            name: name,
            onDone: _close,
          ),
        ),
      if (list.length >= limit)
        _Line('All $limit in use. Delete one to add another.')
      else
        _Item(
          key: ValueKey('$scope:new'),
          add: true,
          text: 'Add a memory',
          open: _open == '$scope:new',
          onTap: () => _toggle('$scope:new'),
          panel: _SavedEditor(global: global, name: name, onDone: _close),
        ),
    ]);
  }
}

/// A row of a memory's card: its [text], which a tap opens [panel] under while [open]. An [add]
/// row is a plus and its words in the accent.
class _Item extends StatelessWidget {
  const _Item({
    super.key,
    required this.text,
    required this.open,
    required this.onTap,
    this.heard,
    this.panel,
    this.add = false,
  });

  final String text;
  final String? heard;
  final bool open;
  final VoidCallback onTap;
  final Widget? panel;
  final bool add;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    const side = FieldCard.inset;
    final words = Text(
      text,
      style: Type.sans(
        16,
        weight: add ? FontWeight.w600 : FontWeight.w400,
        color: add ? t.accent : t.ink,
        height: 1.4,
      ),
    );
    final head = Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: side, vertical: 10),
      child: Row(
        spacing: 12,
        children: [
          if (add) AppIcon('plus', size: IconSize.small, color: t.accent),
          Expanded(child: words),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tappable(
          label: heard ?? text,
          expanded: panel == null ? null : open,
          onTap: onTap,
          child: head,
        ),
        if (open)
          if (panel case final panel?)
            Padding(
              padding: const EdgeInsets.fromLTRB(side, 0, side, 14),
              child: panel,
            ),
      ],
    );
  }
}

/// A line of muted text in a card, where its rows would be.
class _Line extends StatelessWidget {
  const _Line(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FieldCard.inset,
        vertical: 14,
      ),
      child: Text(text, style: Type.sans(15, color: Tokens.of(context).muted)),
    );
  }
}

/// A saved memory's text and where it shows, to add or change it, with Delete for one that is
/// saved.
class _SavedEditor extends StatefulWidget {
  const _SavedEditor({
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
    if (_asking && existing != null) {
      return ConfirmBox(
        text: 'Delete this memory? Chats are no longer shown it.',
        onCancel: () => setState(() => _asking = false),
        onConfirm: () async {
          if (await memory.delete(existing) && mounted) widget.onDone();
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        AppField(
          controller: _text,
          label: 'Memory',
          hint: 'One short fact, such as: Prefers metric units.',
          maxLines: 3,
          autofocus: existing == null,
        ),
        NamedControl(
          'Shown in',
          Segmented<bool>(
            options: [
              (true, 'Every workspace'),
              (false, 'Only ${widget.name}'),
            ],
            value: _global,
            onChanged: (g) => setState(() => _global = g),
          ),
          size: 13.5,
        ),
        if (_problem case final problem?)
          Text(problem, style: Type.sans(13.5, color: t.badfg)),
        ActionRow([
          if (existing != null)
            AppButton(
              'Delete',
              danger: true,
              onPressed: memory.busy
                  ? null
                  : () => setState(() => _asking = true),
            ),
          AppButton('Cancel', onPressed: widget.onDone),
          AppButton(
            existing == null ? 'Add' : 'Save',
            primary: true,
            onPressed: memory.busy ? null : _save,
          ),
        ], alignment: WrapAlignment.start),
      ],
    );
  }
}
