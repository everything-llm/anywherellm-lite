import 'package:flutter/material.dart';

import '../core/copy.dart';
import '../core/schedule.dart';
import 'app_scope.dart';
import 'layout.dart';
import 'links.dart';
import 'list_detail.dart';
import 'shell_popup.dart';
import 'task_sheet.dart';
import 'tokens.dart';
import 'type.dart';
import 'upcoming.dart';
import 'widgets/basics.dart';
import 'widgets/buttons.dart';
import 'widgets/controls.dart';
import 'widgets/list_row.dart';
import 'widgets/phone_page.dart';
import 'widgets/scroll_fades.dart';
import 'widgets/sheet.dart';

/// The question before a task in the Upcoming pane is deleted, in the shell's popup so Back
/// closes it.
class DeleteTask {
  const DeleteTask(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is DeleteTask && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum _Detail { task, edit, create }

/// Upcoming as a page, which [Pane.upcoming] shows on a wide window: its title, how many tasks
/// and that times are in your time zone, with New task where the toolkit lets jobs be made;
/// then the tasks in a list beside the one chosen, as its sheet shows it, or its form while it
/// is edited or a new one made. Delete task asks in a sheet over the window. Where the toolkit
/// only lists the jobs, the list fills the page, read only. Narrower, it is Settings' Upcoming
/// page under a bar of its own.
class UpcomingPane extends StatefulWidget {
  const UpcomingPane({super.key});

  @override
  State<UpcomingPane> createState() => _UpcomingPaneState();
}

class _UpcomingPaneState extends State<UpcomingPane> {
  /// The id of the task chosen, or null for the first.
  String? _chosen;
  _Detail _detail = _Detail.task;

  @override
  void initState() {
    super.initState();
    AppScope.of(context).toolkit.wantJobs();
  }

  void _show(_Detail detail, {String? id}) {
    AppScope.of(context).toolkit.clearChangeProblem();
    setState(() {
      _detail = detail;
      if (id != null) _chosen = id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    if (!Wide.split(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhonePageHeader(
            title: 'Upcoming',
            back: 'Back to the chat',
            onBack: shell.closePane,
            action: const UpcomingAction(),
          ),
          Expanded(
            child: ScrollFades(
              child: SingleChildScrollView(
                padding: Sizes.pageIn(context),
                child: const UpcomingPage(),
              ),
            ),
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: scope.toolkit,
      builder: (context, _) {
        final toolkit = scope.toolkit;
        final jobs = toolkit.jobs;
        final listed = [
          for (final job in jobs ?? const <ScheduledJob>[])
            if (job.id != null) job,
        ];
        final chosen = jobById(listed, _chosen) ?? listed.firstOrNull;
        final writable = toolkit.jobsWritable;
        final detail = !writable
            ? null
            : _detail == _Detail.create
            ? _Detail.create
            : chosen == null
            ? null
            : _detail;
        final Widget body;
        if (jobs == null || toolkit.jobsProblem != null) {
          body = Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Sizes.column),
              child: JobsNotRead(toolkit.jobsProblem),
            ),
          );
        } else if (detail == null) {
          body = Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Sizes.column),
              child: _list(context, jobs, null),
            ),
          );
        } else {
          body = ListDetail(
            list: _list(context, jobs, chosen),
            detail: _card(context, detail, chosen),
          );
        }
        return ShellPopup<DeleteTask>.any(
          // A task gone from a read leaves nothing to ask about.
          present: (open) => jobById(jobs, open.id) != null,
          title: (_) => 'Delete task',
          builder: (context, open, close) => deleteTaskQuestion(
            context,
            open.id,
            onKeep: close,
            onDeleted: close,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, jobs),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: body,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The page's title, how many tasks there are and how their times read, beside New task; and
  /// a way back where no sidebar shows the way out.
  Widget _header(BuildContext context, List<ScheduledJob>? jobs) {
    final scope = AppScope.of(context);
    final writable = scope.toolkit.jobsWritable;
    final (one, many) = writable ? ('task', 'tasks') : ('job', 'jobs');
    return PaneHeader(
      title: 'Upcoming',
      about: [
        if (jobs != null) plural(jobs.length, one, many),
        writable ? 'Times are in your time zone.' : 'Read only here.',
      ].join(' · '),
      back: 'Back to the chat',
      onBack: scope.shell.closePane,
      action: writable
          ? AppButton(
              'New task',
              primary: true,
              compact: true,
              leading: 'plus',
              onPressed: () => _show(_Detail.create),
            )
          : null,
    );
  }

  /// The tasks in a card, the one [chosen] marked, then Edit in AnythingLLM's web page; or,
  /// with none, what a task is.
  Widget _list(
    BuildContext context,
    List<ScheduledJob> jobs,
    ScheduledJob? chosen,
  ) {
    final scope = AppScope.of(context);
    final writable = scope.toolkit.jobsWritable;
    final now = DateTime.now();
    return ScrollFades(
      child: ListView(
        children: [
          if (scope.toolkit.changeProblem case final problem?
              when _detail == _Detail.task && chosen == null) ...[
            AlertBox.notice(AlertKind.bad, problem),
            const SizedBox(height: 12),
          ],
          if (jobs.isEmpty)
            NoTasks(writable: writable, onNew: () => _show(_Detail.create))
          else
            ListCard([for (final job in jobs) _row(context, job, chosen, now)]),
          if (scope.settings.configured) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextAction(
                'external',
                'Edit in AnythingLLM\'s web page',
                () => openServerPage(context),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// A task: its name over its schedule and when it runs next, Off, or when its last run
  /// failed, in red. It opens where the toolkit lets the task be changed.
  Widget _row(
    BuildContext context,
    ScheduledJob job,
    ScheduledJob? chosen,
    DateTime now,
  ) {
    final t = Tokens.of(context);
    final writable = AppScope.of(context).toolkit.jobsWritable;
    final (text: status, :failed) = job.status(now);
    final schedule = describeSchedule(job.cron, now);
    return ListRow(
      key: ValueKey(job.id ?? job.name),
      title: job.name,
      aboutSpan: TextSpan(
        text: schedule,
        children: [
          if (status != null)
            TextSpan(
              text: '\n$status',
              style: TextStyle(color: failed ? t.danger : t.muted),
            ),
        ],
      ),
      aboutLines: 4,
      heard: [job.name, schedule, ?status].join(', '),
      selected: chosen != null && job.id == chosen.id,
      onTap: writable && job.id != null
          ? () => _show(_Detail.task, id: job.id)
          : null,
    );
  }

  /// The chosen task as its sheet shows it, its form while it is edited, or a new task's form,
  /// in a card under its name; the task's own says when it runs and holds its On switch.
  Widget _card(BuildContext context, _Detail detail, ScheduledJob? chosen) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final toolkit = scope.toolkit;
    final id = chosen?.id;
    final Widget content = switch (detail) {
      _Detail.create => TaskForm(
        key: const ValueKey('new task'),
        onDone: () => _show(_Detail.task),
      ),
      _Detail.edit => TaskForm(
        key: ValueKey(('edit', id)),
        existing: chosen,
        onDone: () => _show(_Detail.task),
      ),
      _Detail.task when id != null => TaskDetail.beside(
        id,
        key: ValueKey(id),
        onEdit: () => _show(_Detail.edit),
        onDelete: () => scope.shell.togglePopup(DeleteTask(id)),
      ),
      _ => const SizedBox.shrink(),
    };
    final task = detail == _Detail.task ? chosen : null;
    return DetailCard(
      title: switch (detail) {
        _Detail.create => 'New task',
        _Detail.edit => 'Edit task',
        _Detail.task => chosen?.name ?? 'Task',
      },
      titleLines: 2,
      about: task == null ? null : _when(context, task),
      actions: [
        if (task != null) ...[
          ExcludeSemantics(child: Text('On', style: Type.note(t.ink))),
          AppSwitch(
            value: task.enabled,
            label: 'Task on',
            onChanged: toolkit.busy || id == null
                ? null
                : (on) => toolkit.setEnabled(id, on),
          ),
        ],
      ],
      // The task's prompt and runs are wells on the card, as a sheet's cards are.
      child: SheetCards(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Sizes.column),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  /// When [job] runs, and when it runs next, is off, or last failed, in red, on one line under
  /// its name.
  Widget _when(BuildContext context, ScheduledJob job) {
    final t = Tokens.of(context);
    final now = DateTime.now();
    final (:text, :failed) = job.status(now);
    return Text.rich(
      TextSpan(
        text: describeSchedule(job.cron, now),
        children: [
          if (text != null)
            TextSpan(
              text: ' · $text',
              style: TextStyle(color: failed ? t.danger : t.ink),
            ),
        ],
      ),
      style: Type.note(t.ink),
    );
  }
}
