import 'package:flutter/material.dart';

import '../core/copy.dart';
import '../core/schedule.dart';
import 'app_scope.dart';
import 'state/toolkit_controller.dart';
import 'links.dart';
import 'settings/rows.dart';
import 'settings/settings_pages.dart';
import 'state/notice.dart';
import 'shell_popup.dart';
import 'task_sheet.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/basics.dart';
import 'widgets/buttons.dart';
import 'icons.dart';
import 'widgets/fields.dart';
import 'widgets/tappable.dart';

/// Settings' Upcoming page: each job the server runs on a schedule, with its schedule in local
/// time, when it runs next and how its last run went. Where the toolkit lets jobs be changed
/// ([ToolkitController.jobsWritable]) the header's plus ([UpcomingAction]) makes one and a row
/// opens its [TaskSheet]; otherwise it is read only, with a way to AnythingLLM's web page. It
/// reads the jobs afresh as it opens, through the toolkit.
class UpcomingPage extends StatefulWidget {
  const UpcomingPage({super.key});

  @override
  State<UpcomingPage> createState() => _UpcomingPageState();
}

class _UpcomingPageState extends State<UpcomingPage> {
  @override
  void initState() {
    super.initState();
    AppScope.of(context).toolkit.wantJobs();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final toolkit = scope.toolkit;
    ScheduledJob? jobOf(TaskSheet open) => jobById(toolkit.jobs, open.id);
    return ListenableBuilder(
      listenable: toolkit,
      builder: (context, _) => ShellPopup<TaskSheet>.any(
        // A task gone from a read leaves nothing to show, so its sheet closes.
        present: (open) => open.id == null || jobOf(open) != null,
        title: (open) => switch (open) {
          TaskSheet(id: null) => 'New task',
          TaskSheet(editing: true) => 'Edit task',
          _ => jobOf(open)?.name ?? 'Task',
        },
        builder: (context, open, _) => switch (open) {
          TaskSheet(editing: true) => TaskForm(
            key: ValueKey(open),
            existing: jobOf(open),
          ),
          TaskSheet(:final id?) => TaskDetail(id, key: ValueKey(open)),
          _ => const TaskForm(),
        },
        child: _body(context, toolkit),
      ),
    );
  }

  Widget _body(BuildContext context, ToolkitController toolkit) {
    final scope = AppScope.of(context);
    final jobs = toolkit.jobs;
    final now = DateTime.now();
    final writable = toolkit.jobsWritable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (toolkit.changeProblem case final problem?) ...[
          AlertBox.notice(AlertKind.bad, problem),
          const SizedBox(height: 12),
        ],
        if (jobs == null || toolkit.jobsProblem != null)
          JobsNotRead(toolkit.jobsProblem)
        else if (jobs.isEmpty)
          NoTasks(writable: writable)
        else
          // One card, a rule between its jobs, as the Lite prototype draws it.
          FieldCard([
            for (final job in jobs)
              _JobRow(
                job,
                now: now,
                onTap: writable && job.id != null
                    ? () => openTask(scope, TaskSheet(id: job.id))
                    : null,
              ),
          ]),
        const SizedBox(height: 20),
        HelpText(writable ? 'Times are in your time zone.' : 'Read only here.'),
        const SizedBox(height: 20),
        if (scope.settings.configured)
          ActionRow(even: true, [
            AppButton(
              'Edit in AnythingLLM\'s web page',
              icon: 'external',
              onPressed: () => openServerPage(context),
            ),
          ]),
      ],
    );
  }
}

/// Upcoming's header button, New task, where the toolkit lets jobs be made, and the header's
/// empty end otherwise. It follows the toolkit itself, so the header around it need not.
class UpcomingAction extends StatelessWidget {
  const UpcomingAction({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.toolkit,
      builder: (context, _) => scope.toolkit.jobsWritable
          ? IconBtn.header(
              'plus',
              tooltip: 'New task',
              onPressed: () => openTask(scope, const TaskSheet()),
            )
          : const SizedBox(width: 48),
    );
  }
}

/// How many jobs there are and when the next runs, or null until read: the line under
/// Upcoming's row in Settings. They are tasks where the toolkit lets them be changed.
String? upcomingSummary(ToolkitController toolkit) {
  final jobs = toolkit.jobs;
  if (jobs == null) return null;
  final now = DateTime.now();
  final next = [
    for (final job in jobs)
      if (job.enabled) ?job.nextRun,
  ]..sort();
  final (one, many) = toolkit.jobsWritable
      ? ('task', 'tasks')
      : ('job', 'jobs');
  return [
    plural(jobs.length, one, many),
    if (next.isNotEmpty) 'next ${whenText(next.first, now)}',
  ].join(' · ');
}

/// What Upcoming shows before it has something to: why its read failed, with a way to the
/// Connection page, or Reading… while it reads.
class JobsNotRead extends StatelessWidget {
  const JobsNotRead(this.problem, {super.key});

  final Notice? problem;

  @override
  Widget build(BuildContext context) {
    final problem = this.problem;
    if (problem == null) {
      return const HelpText('Reading…', status: true);
    }
    final shell = AppScope.of(context).shell;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        AlertBox.notice(AlertKind.warn, problem),
        AppButton(
          'Open Connection',
          onPressed: () => shell.settingsOpen
              ? shell.showSettingsPage(SettingsPage.connection)
              : shell.openSettings(SettingsPage.connection),
        ),
      ],
    );
  }
}

/// One job: its name, then its schedule and when it runs next, or when its last run failed, in
/// red, cut short where it is too long.
class _JobRow extends StatelessWidget {
  const _JobRow(this.job, {required this.now, this.onTap});

  final ScheduledJob job;
  final DateTime now;

  /// Opens the job's sheet, or null for a row that only shows it.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final (:text, :failed) = job.status(now);
    final when = text;
    final about = describeSchedule(job.cron, now);
    final row = InfoRow(
      job.name,
      aboutLines: 4,
      aboutSpan: TextSpan(
        text: about,
        children: [
          if (when != null) ...[
            const TextSpan(text: '\n'),
            TextSpan(
              text: when,
              style: failed ? TextStyle(color: t.danger) : null,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return Tappable(
      label: '${[job.name, about, ?when].join(', ')}. Open',
      onTap: onTap,
      child: Row(
        children: [
          Expanded(child: row),
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: AppIcon('chevron', size: IconSize.xs, color: t.muted),
          ),
        ],
      ),
    );
  }
}

/// What shows before anything is scheduled: a clock, what a task is, and where a task is made
/// from, so the empty page says what to do rather than only that there is nothing.
class NoTasks extends StatelessWidget {
  const NoTasks({super.key, required this.writable, this.onNew});

  /// Whether tasks can be made here, which adds a New task button.
  final bool writable;

  /// Opens a new task's form, in place of its sheet.
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final scope = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.accentSoft,
              shape: BoxShape.circle,
            ),
            child: AppIcon('clock', size: IconSize.large, color: t.accent),
          ),
          const SizedBox(height: 4),
          Text(
            'No scheduled tasks',
            textAlign: TextAlign.center,
            style: Type.title(t.ink),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              writable
                  ? 'A task runs on a schedule, such as a summary every morning. '
                        'Make one here, or ask the agent to.'
                  : 'Nothing is scheduled on your server.',
              textAlign: TextAlign.center,
              style: Type.note(t.ink),
            ),
          ),
          if (writable) ...[
            const SizedBox(height: 8),
            AppButton(
              'New task',
              primary: true,
              leading: 'plus',
              onPressed: onNew ?? () => openTask(scope, const TaskSheet()),
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens [sheet] over Upcoming, taking away why an earlier change failed, which belonged to the
/// task it was about.
void openTask(AppScope scope, TaskSheet sheet) {
  scope.toolkit.clearChangeProblem();
  scope.shell.togglePopup(sheet);
}
