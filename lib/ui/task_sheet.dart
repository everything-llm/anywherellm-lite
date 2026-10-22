import 'dart:async';

import 'package:flutter/material.dart';

import '../core/copy.dart';
import '../core/schedule.dart';
import '../core/schedule_spec.dart';
import 'app_scope.dart';
import 'icons.dart';
import 'layout.dart';
import 'settings/rows.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/basics.dart';
import 'widgets/buttons.dart';
import 'widgets/fields.dart';
import 'widgets/list_row.dart';
import 'widgets/segmented.dart';
import 'widgets/sheet.dart';
import 'widgets/tappable.dart';

/// Upcoming's sheet for one scheduled task, or a new one, in the shell's popup so Back closes
/// it: the task with its runs, or, [editing], its form.
class TaskSheet {
  const TaskSheet({this.id, this.editing = false});

  /// The task's id, or null for a new one.
  final String? id;
  final bool editing;

  @override
  bool operator ==(Object other) =>
      other is TaskSheet && other.id == id && other.editing == editing;

  @override
  int get hashCode => Object.hash(id, editing);
}

/// A task as AnythingLLM lists it, found by [id], or null when it is gone.
ScheduledJob? jobById(List<ScheduledJob>? jobs, String? id) =>
    id == null ? null : jobs?.where((j) => j.id == id).firstOrNull;

/// A scheduled task in its sheet: when it runs, whether it is on, Run now, Edit and Delete, what
/// it does and how its latest runs went. Edit opens the form's sheet and Delete asks in this one.
class TaskDetail extends StatefulWidget {
  const TaskDetail(this.id, {super.key})
    : onEdit = null,
      onDelete = null,
      wide = false;

  /// The task as a list's detail shows it, under a header that says when it runs and holds its
  /// On switch: Run now, Edit, which calls [onEdit], and Delete task, which calls [onDelete], in
  /// one row.
  const TaskDetail.beside(
    this.id, {
    super.key,
    required VoidCallback this.onEdit,
    required VoidCallback this.onDelete,
  }) : wide = true;

  final String id;
  final bool wide;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  State<TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends State<TaskDetail> {
  bool _asking = false;
  late final _toolkit = AppScope.of(context).toolkit;

  @override
  void initState() {
    super.initState();
    // Reads the runs, so a run that began before this sheet opened, or while the form over it
    // was open, is followed to its end. [ToolkitController.runNow] follows the run it starts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_toolkit.follow(widget.id));
    });
  }

  @override
  void dispose() {
    // A run's progress shows only here.
    _toolkit.stopFollowing();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    return ListenableBuilder(
      listenable: scope.toolkit,
      builder: (context, _) {
        final toolkit = scope.toolkit;
        final job = jobById(toolkit.jobs, widget.id);
        if (job == null) return const SizedBox.shrink();
        final now = DateTime.now();
        final runs = toolkit.runs[widget.id];
        final running = runs?.firstOrNull?.running ?? false;
        final status = job.status(now);
        // Off says what it means here, where the switch that turns it on is.
        final when = !status.failed && !job.enabled
            ? 'Off: nothing runs it until you turn it on.'
            : status.text ?? '';
        final run = AppButton(
          running ? 'Running…' : 'Run now',
          onPressed: toolkit.busy || running
              ? null
              : () => toolkit.runNow(widget.id),
        );
        final edit = AppButton(
          'Edit',
          onPressed:
              widget.onEdit ??
              () => shell.togglePopup(TaskSheet(id: widget.id, editing: true)),
        );
        final delete = AppButton(
          'Delete task',
          danger: true,
          onPressed: toolkit.busy
              ? null
              : widget.onDelete ?? () => setState(() => _asking = true),
        );
        final prompt = job.prompt.isEmpty ? 'Nothing saved.' : job.prompt;
        final tools = job.tools > 0
            ? CardCaption(
                'May use ${plural(job.tools, 'tool', 'tools')}, which only AnythingLLM\'s web page sets.',
              )
            : null;
        if (widget.wide) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                if (toolkit.changeProblem case final problem?)
                  AlertBox.notice(AlertKind.bad, problem),
                Wrap(spacing: 8, runSpacing: 8, children: [run, edit, delete]),
                const SheetLabel('What it does'),
                FieldCard([CardWords(prompt)]),
                ?tools,
                const SheetLabel('Recent runs'),
                if (runs == null)
                  const HelpText('Reading…', status: true)
                else if (runs.isEmpty)
                  const CardCaption('No runs yet.')
                else
                  FieldCard([
                    for (final run in runs) _RunRow(run, now: now, wide: true),
                  ]),
              ],
            ),
          );
        }
        // It scrolls where large text leaves the sheet too short for what it holds.
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              if (toolkit.changeProblem case final problem?)
                AlertBox.notice(AlertKind.bad, problem),
              FieldCard([
                InfoRow(
                  describeSchedule(job.cron, now),
                  aboutSpan: TextSpan(text: when),
                ),
              ]),
              FieldCard([
                FieldRow.toggle(
                  label: 'On',
                  help: job.enabled ? 'Runs on its schedule' : 'Paused',
                  switchLabel: 'Task on',
                  value: job.enabled,
                  onChanged: toolkit.busy
                      ? null
                      : (on) => toolkit.setEnabled(widget.id, on),
                ),
              ]),
              ActionRow(even: true, [run, edit]),
              const SheetLabel('What it does'),
              FieldCard([CardWords(prompt)]),
              ?tools,
              const SheetLabel('Recent runs'),
              if (runs == null)
                const HelpText('Reading…', status: true)
              else if (runs.isEmpty)
                const CardCaption('No runs yet.')
              else
                FieldCard([for (final run in runs) _RunRow(run, now: now)]),
              if (_asking)
                deleteTaskQuestion(
                  context,
                  widget.id,
                  onKeep: () => setState(() => _asking = false),
                  // Only this sheet closes, not a popup opened while it waited.
                  onDeleted: switch (shell.popup.value) {
                    final sheet? => () => shell.closePopup(sheet),
                    null => () {},
                  },
                )
              else
                delete,
            ],
          ),
        );
      },
    );
  }
}

/// One run: when it started, then what it left, in red for one that failed; [wide] sets the
/// two side by side.
class _RunRow extends StatelessWidget {
  const _RunRow(this.run, {required this.now, this.wide = false});

  final JobRun run;
  final DateTime now;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final at = run.startedAt;
    final when = Text(
      capitalized(at == null ? 'Run' : whenText(at, now)),
      style: Type.body(t.ink),
    );
    final result = run.running ? 'Running…' : run.result ?? '';
    final left = result.isEmpty
        ? null
        : Text(
            result,
            style: Type.note(
              run.wentWell == false
                  ? t.danger
                  : run.running
                  ? t.accent
                  : t.ink,
            ),
          );
    if (wide) {
      return Container(
        constraints: const BoxConstraints(minHeight: ListRow.height),
        padding: const EdgeInsets.symmetric(horizontal: FieldCard.inset),
        child: Row(
          spacing: 16,
          children: [
            SizedBox(width: 152, child: when),
            Expanded(child: left ?? const SizedBox.shrink()),
          ],
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(minHeight: Sizes.cardRow),
      padding: const EdgeInsets.symmetric(
        horizontal: FieldCard.inset,
        vertical: 10,
      ),
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [when, ?left],
      ),
    );
  }
}

/// The question before the task [id] is deleted: Keep calls [onKeep], and Delete deletes it and,
/// once it is gone, calls [onDeleted].
Widget deleteTaskQuestion(
  BuildContext context,
  String id, {
  required VoidCallback onKeep,
  required VoidCallback onDeleted,
}) {
  final toolkit = AppScope.of(context).toolkit;
  return SheetQuestion(
    'Delete ${jobById(toolkit.jobs, id)?.name ?? 'this task'}? Its earlier runs go with it.',
    onKeep: onKeep,
    onConfirm: toolkit.busy
        ? null
        : () async {
            if (await toolkit.removeJob(id)) onDeleted();
          },
  );
}

/// A new task, or [existing] changed: its name, what it asks and when, as the person writes it,
/// which becomes a UTC cron for AnythingLLM.
class TaskForm extends StatefulWidget {
  const TaskForm({super.key, this.existing, this.onDone});

  final ScheduledJob? existing;

  /// Called once the form is saved or cancelled, in place of closing its sheet.
  final VoidCallback? onDone;

  @override
  State<TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<TaskForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _prompt = TextEditingController(
    text: widget.existing?.prompt ?? '',
  );
  late ScheduleSpec _spec = switch (widget.existing) {
    final job? => ScheduleSpec.fromCron(job.cron, DateTime.now()),
    null => const ScheduleSpec(),
  };
  late final _cron = TextEditingController(text: _spec.cron);
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    _cron.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final scope = AppScope.of(context);
    final now = DateTime.now();
    final existing = widget.existing;
    final name = _name.text.trim();
    final prompt = _prompt.text.trim();
    final cron = _spec.toCron(now);
    final problem = name.isEmpty
        ? 'Give it a name.'
        : prompt.isEmpty
        ? 'Say what it should do.'
        : _spec.problem();
    setState(() => _problem = problem);
    if (problem != null || cron == null) return;
    // Only this sheet closes, not a popup opened while it saved.
    final sheet = scope.shell.popup.value;
    final done = await scope.toolkit.saveJob(
      existing,
      JobDraft(name: name, prompt: prompt, cron: cron),
    );
    if (!done) return;
    if (widget.onDone case final onDone?) {
      if (mounted) onDone();
    } else if (sheet != null) {
      scope.shell.closePopup(sheet);
    }
  }

  void _cancel() {
    if (widget.onDone case final onDone?) return onDone();
    final shell = AppScope.of(context).shell;
    final id = widget.existing?.id;
    if (id == null) {
      shell.closePopup();
    } else {
      shell.togglePopup(TaskSheet(id: id));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _spec.hour, minute: _spec.minute),
    );
    if (picked != null && mounted) {
      setState(() {
        _spec = _spec.copyWith(hour: picked.hour, minute: picked.minute);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final toolkit = scope.toolkit;
    final now = DateTime.now();
    final existing = widget.existing;
    final problem = _problem ?? _spec.problem();
    // It scrolls where the keyboard or large text leaves the sheet too short for the form.
    return SingleChildScrollView(
      child: ListenableBuilder(
        listenable: toolkit,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            if (toolkit.changeProblem case final failed?)
              AlertBox.notice(AlertKind.bad, failed),
            AppField(
              controller: _name,
              label: 'Name',
              hint: 'Morning brief',
              autofocus: existing == null,
              onChanged: (_) => setState(() => _problem = null),
            ),
            AppField(
              controller: _prompt,
              label: 'What should it do?',
              hint: 'Summarise today: the weather, the bins, anything due.',
              maxLines: 4,
              onChanged: (_) => setState(() => _problem = null),
            ),
            const SheetLabel('When'),
            Segmented<Repeat>(
              options: const [
                (Repeat.daily, 'Daily'),
                (Repeat.weekly, 'Weekly'),
                (Repeat.custom, 'Custom'),
              ],
              value: _spec.repeat,
              onChanged: (repeat) => setState(() {
                _spec = _spec.copyWith(repeat: repeat);
                _problem = null;
              }),
            ),
            if (_spec.repeat == Repeat.weekly)
              _DayChips(
                _spec.days,
                onChanged: (days) => setState(() {
                  _spec = _spec.copyWith(days: days);
                  _problem = null;
                }),
              ),
            if (_spec.repeat == Repeat.custom)
              AppField(
                controller: _cron,
                label: 'Cron schedule',
                hint: '0 6 * * 1',
                onChanged: (text) => setState(() {
                  _spec = _spec.copyWith(cron: text);
                  _problem = null;
                }),
              )
            else
              _Picker(
                label: 'Time',
                value: clockText(DateTime(0, 1, 1, _spec.hour, _spec.minute)),
                icon: 'clock',
                onTap: _pickTime,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                problem ?? _spec.caption(now),
                key: const ValueKey('schedule caption'),
                style: Type.note(problem == null ? t.ink : t.danger),
              ),
            ),
            ActionRow(even: true, [
              AppButton('Cancel', onPressed: _cancel),
              AppButton(
                'Save',
                primary: true,
                onPressed: toolkit.busy ? null : _save,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// A field that opens a picker: [label] heard with its [value], drawn as a field is, with
/// [icon] at its end.
class _Picker extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.value,
    required this.onTap,
    this.icon,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: '$label: $value. Change',
      onTap: onTap,
      radius: BorderRadius.circular(Sizes.control),
      child: Container(
        height: Sizes.field,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: fieldFill(context),
          border: Border.all(color: fieldEdge(context)),
          borderRadius: BorderRadius.circular(Sizes.control),
        ),
        child: Row(
          children: [
            Expanded(child: Text(value, style: Type.body(t.ink))),
            if (icon case final icon?) AppIcon(icon, color: t.muted),
          ],
        ),
      ),
    );
  }
}

/// Seven round buttons, Monday first, each a weekday switched on or off.
class _DayChips extends StatelessWidget {
  const _DayChips(this.days, {required this.onChanged});

  final Set<int> days;
  final ValueChanged<Set<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i++)
          Tappable(
            label: weekdayNames[i],
            toggled: days.contains(i + 1),
            onTap: () => onChanged({
              ...days.where((d) => d != i + 1),
              if (!days.contains(i + 1)) i + 1,
            }),
            shape: const CircleBorder(),
            color: days.contains(i + 1) ? t.accent : t.sunken,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Text(
                  weekdayNames[i][0],
                  style: Type.caption(
                    days.contains(i + 1) ? t.onAccent : t.ink,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
