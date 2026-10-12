import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/memory.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
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

/// What chats are shown about the person and what the agent can look up, for one workspace,
/// picked at the top: AnythingLLM's saved memories, with its switches, those for every workspace
/// and the workspace's own; then the everythingllm host's long-term memory, searched by meaning,
/// its facts and the files read in. A row opens under itself to change, delete or forget it, one
/// at a time.
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key});

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  /// The row open under itself: `g:<id>` or `w:<id>` for a saved memory, `g:new` or `w:new` for
  /// a new one, `fact:<id>`, `file:<path>`, or `remember`.
  String? _open;

  final _search = TextEditingController();
  Timer? _searching;

  @override
  void dispose() {
    _searching?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _toggle(String key) => setState(() => _open = _open == key ? null : key);

  void _close() => setState(() => _open = null);

  void _find(String text, {bool now = false}) {
    _searching?.cancel();
    final memory = AppScope.of(context).memory;
    if (now) {
      unawaited(memory.recall(text));
    } else {
      _searching = Timer(
        const Duration(milliseconds: 400),
        () => unawaited(memory.recall(text)),
      );
    }
  }

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
        if (memory.query.isEmpty && _search.text.trim().isNotEmpty) {
          _search.clear();
        }
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
                          _search.clear();
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
            const SubHead('Long-term memory'),
            const PageNote(
              'As many facts as you like, kept beside AnythingLLM. No chat is shown them; '
              'the agent looks here when a question needs it.',
            ),
            ..._long(memory, name),
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
              large: true,
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
                large: true,
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

  List<Widget> _long(MemoryController memory, String name) {
    final long = memory.long;
    final hits = memory.hits;
    if (memory.longUnavailable) {
      return const [
        PageNote(
          'This server has no long-term memory. It comes with the everythingllm host.',
        ),
      ];
    }
    return [
      if (memory.longProblem case final problem?)
        AlertBox(AlertKind.bad, problem.title, text: problem.text),
      if (memory.longNote case final note?) HelpText(note, status: true),
      if (long == null)
        if (memory.loading) const HelpText('Loading…', status: true) else ...[]
      else ...[
        AppField(
          controller: _search,
          label: 'Find a long-term fact by meaning',
          hint: 'Find by meaning',
          icon: 'search',
          onChanged: _find,
          onSubmitted: (text) => _find(text, now: true),
        ),
        if (memory.query.isNotEmpty) ...[
          if (hits == null)
            HelpText(
              memory.recalling ? 'Searching…' : 'The search did not finish.',
              status: true,
            )
          else if (hits.isEmpty)
            const PageNote('Nothing kept is close to that.')
          else ...[
            const SectionLabel('Closest first'),
            FieldCard([
              for (final hit in hits)
                if (hit.fact case final fact?)
                  _factItem(fact, name, score: hit.score)
                else
                  _Item(
                    key: ValueKey('part:${hit.path}:${hit.part}'),
                    text: hit.text,
                    about:
                        '${_percent(hit.score)} · ${hit.path}, part ${hit.part}',
                    lines: 3,
                    open: false,
                    onTap: null,
                  ),
            ]),
          ],
        ] else ...[
          SectionLabel(
            long.count > long.facts.length
                ? 'Facts · newest ${long.facts.length} of ${long.count}'
                : 'Facts · ${long.count}',
          ),
          FieldCard([
            for (final fact in long.facts) _factItem(fact, name),
            _Item(
              key: const ValueKey('remember'),
              add: true,
              text: 'Remember something',
              open: _open == 'remember',
              onTap: () => _toggle('remember'),
              panel: _RememberEditor(name: name, onDone: _close),
            ),
          ]),
          SectionLabel('Files read in · ${long.files.length}'),
          FieldCard([
            for (final file in long.waiting)
              _Item(
                key: ValueKey('waiting:${file.path}'),
                text: file.path,
                mono: true,
                about: 'Being read · ${_parts(file.parts)} to go',
                open: false,
                onTap: null,
              ),
            for (final failed in long.failed)
              _Item(
                key: ValueKey('failed:${failed.path}'),
                text: failed.path,
                mono: true,
                about: 'Could not read it: ${failed.error}',
                open: false,
                onTap: null,
              ),
            for (final file in long.files)
              _Item(
                key: ValueKey('file:${file.path}'),
                text: file.path,
                mono: true,
                about: [
                  _parts(file.parts),
                  if (file.ingested case final kept?)
                    keptText(kept, DateTime.now()),
                ].join(' · '),
                heard: '${file.path}. Forget its text',
                open: _open == 'file:${file.path}',
                onTap: () => _toggle('file:${file.path}'),
                panel: ConfirmBox(
                  text:
                      'Forget the text read in from ${file.path}? The file stays in '
                      'the sandbox.',
                  action: 'Forget',
                  onCancel: _close,
                  onConfirm: () async {
                    if (await memory.forgetFile(file.path)) _close();
                  },
                ),
              ),
            if (long.files.isEmpty &&
                long.waiting.isEmpty &&
                long.failed.isEmpty)
              const _Line(
                'No files yet. Ask the agent to read one in, and it shows here.',
              ),
          ]),
        ],
      ],
    ];
  }

  Widget _factItem(LongFact fact, String name, {double? score}) {
    final memory = AppScope.of(context).memory;
    final key = 'fact:${fact.id}';
    return _Item(
      key: ValueKey('$key:${score != null}'),
      text: fact.text,
      about: [
        if (score != null) _percent(score),
        fact.global ? 'Every workspace' : 'Only $name',
        if (fact.created case final kept?) keptText(kept, DateTime.now()),
      ].join(' · '),
      heard: '${fact.text} Forget it',
      open: _open == key,
      onTap: () => _toggle(key),
      panel: ConfirmBox(
        text:
            'Forget this fact? The agent can no longer recall it. To change it, forget it '
            'and remember the new one.',
        action: 'Forget',
        onCancel: _close,
        onConfirm: () async {
          if (await memory.forgetFact(fact)) _close();
        },
      ),
    );
  }

  static String _percent(double score) => '${(score * 100).round()}% match';

  static String _parts(int n) => n == 1 ? '1 part' : '$n parts';
}

/// A row of a memory's card: its [text], and [about] under it, which a tap opens [panel] under
/// while [open]. An [add] row is a plus and its words in the accent.
class _Item extends StatelessWidget {
  const _Item({
    super.key,
    required this.text,
    required this.open,
    required this.onTap,
    this.about,
    this.heard,
    this.panel,
    this.add = false,
    this.mono = false,
    this.lines,
  });

  final String text;
  final String? about;
  final String? heard;
  final bool open;
  final VoidCallback? onTap;
  final Widget? panel;
  final bool add;
  final bool mono;

  /// The lines [text] may take before it is cut short, or null for all of it.
  final int? lines;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final phone = ScreenClass.ofContext(context).isPhone;
    final side = phone ? FieldCard.inset : 16.0;
    final size = phone ? 16.0 : 14.5;
    final words = Text(
      text,
      maxLines: lines,
      overflow: lines == null ? null : TextOverflow.ellipsis,
      style: mono
          ? Type.mono(size - 1.5, color: t.ink)
          : Type.sans(
              size,
              weight: add ? FontWeight.w600 : FontWeight.w400,
              color: add ? t.accent : t.ink,
              height: 1.4,
            ),
    );
    final head = Container(
      constraints: BoxConstraints(minHeight: phone ? 60 : 48),
      padding: EdgeInsets.symmetric(horizontal: side, vertical: 10),
      child: Row(
        spacing: 12,
        children: [
          if (add) AppIcon('plus', size: IconSize.small, color: t.accent),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                words,
                if (about case final about?)
                  Text(
                    about,
                    style: Type.sans(phone ? 13 : 12.5, color: t.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onTap == null)
          Semantics(container: true, child: head)
        else
          Tappable(
            label: heard ?? text,
            expanded: panel == null ? null : open,
            onTap: onTap,
            child: head,
          ),
        if (open)
          if (panel case final panel?)
            Padding(
              padding: EdgeInsets.fromLTRB(side, 0, side, 14),
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
    final phone = ScreenClass.ofContext(context).isPhone;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: phone ? FieldCard.inset : 16,
        vertical: 14,
      ),
      child: Text(
        text,
        style: Type.sans(phone ? 15 : 13.5, color: Tokens.of(context).muted),
      ),
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

/// A new long-term fact and whom it is kept for.
class _RememberEditor extends StatefulWidget {
  const _RememberEditor({required this.name, required this.onDone});

  final String name;
  final VoidCallback onDone;

  @override
  State<_RememberEditor> createState() => _RememberEditorState();
}

class _RememberEditorState extends State<_RememberEditor> {
  final _text = TextEditingController();
  bool _global = false;
  String? _problem;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _remember() async {
    final text = _text.text.trim();
    final problem = text.isEmpty
        ? 'Write the fact first.'
        : text.length > memoryTextMax
        ? 'Keep it to $memoryTextMax characters.'
        : null;
    setState(() => _problem = problem);
    if (problem != null) return;
    final memory = AppScope.of(context).memory;
    if (await memory.remember(text, global: _global) && mounted) {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final memory = AppScope.of(context).memory;
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        AppField(
          controller: _text,
          label: 'Fact',
          hint: 'One short fact, such as: Takes coffee black.',
          maxLines: 3,
          autofocus: true,
        ),
        NamedControl(
          'Kept for',
          Segmented<bool>(
            options: [
              (false, 'Only ${widget.name}'),
              (true, 'Every workspace'),
            ],
            value: _global,
            onChanged: (g) => setState(() => _global = g),
          ),
          size: 13.5,
        ),
        if (_problem case final problem?)
          Text(problem, style: Type.sans(13.5, color: t.badfg)),
        ActionRow([
          AppButton('Cancel', onPressed: widget.onDone),
          AppButton(
            'Remember',
            primary: true,
            onPressed: memory.busy ? null : _remember,
          ),
        ], alignment: WrapAlignment.start),
      ],
    );
  }
}
