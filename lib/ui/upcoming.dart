import 'package:flutter/material.dart';

import '../core/schedule.dart';
import 'app_scope.dart';
import 'state/toolkit_controller.dart';
import 'layout.dart';
import 'links.dart';
import 'settings/rows.dart';
import 'task_sheet.dart';
import 'toolkit_page.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/basics.dart';
import 'widgets/buttons.dart';
import 'icons.dart';
import 'widgets/fields.dart';
import 'widgets/sheet.dart';
import 'widgets/tappable.dart';

/// A phone's Upcoming: each job the server runs on a schedule, with its schedule in local time,
/// when it runs next and how its last run went. Where the toolkit lets jobs be changed
/// ([ToolkitController.jobsWritable]) a plus makes one and a row opens its [TaskSheet];
/// otherwise it is read only, with a way to AnythingLLM's web page. It reads the jobs afresh as
/// it opens, through the toolkit.
class UpcomingPage extends StatelessWidget {
  const UpcomingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final toolkit = scope.toolkit;
    final shell = scope.shell;
    return ListenableBuilder(
      listenable: Listenable.merge([toolkit, shell.popup]),
      // Only the sheet follows the popup, so opening one leaves the list as it is.
      child: ListenableBuilder(
        listenable: toolkit,
        builder: (context, _) => ToolkitPageFrame(
          title: 'Upcoming',
          read: toolkit.readJobs,
          action: toolkit.jobsWritable
              ? IconBtn.header(
                  'plus',
                  tooltip: 'New task',
                  onPressed: () => openTask(scope, const TaskSheet()),
                )
              : null,
          body: _body(context, toolkit),
        ),
      ),
      builder: (context, page) {
        final open = switch (shell.popup.value) {
          final TaskSheet sheet => sheet,
          _ => null,
        };
        final job = jobById(toolkit.jobs, open?.id);
        // A task gone from a read leaves no sheet to close, so the popup goes too.
        if (open != null &&
            open.id != null &&
            job == null &&
            toolkit.jobs != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => shell.closePopup(open),
          );
        }
        return PopupSheet(
          open: open != null && (open.id == null || job != null),
          onClose: shell.closePopup,
          title: switch (open) {
            null => 'Task',
            TaskSheet(id: null) => 'New task',
            TaskSheet(editing: true) => 'Edit task',
            _ => job?.name ?? 'Task',
          },
          sheet: (context) => switch (open) {
            TaskSheet(editing: true) => TaskForm(
              key: ValueKey(open),
              existing: job,
            ),
            TaskSheet(:final id?) => TaskDetail(id, key: ValueKey(open)),
            _ => const TaskForm(),
          },
          child: page!,
        );
      },
    );
  }

  Widget _body(BuildContext context, ToolkitController toolkit) {
    final scope = AppScope.of(context);
    final jobs = toolkit.jobs;
    final now = DateTime.now();
    final writable = toolkit.jobsWritable;
    return ListView(
      padding: Sizes.pageIn(context),
      children: [
        if (toolkit.changeProblem case final problem?) ...[
          AlertBox.notice(AlertKind.bad, problem),
          const SizedBox(height: 12),
        ],
        if (jobs == null || toolkit.jobsProblem != null)
          NotRead(toolkit.jobsProblem)
        else if (jobs.isEmpty)
          _NoTasks(writable: writable)
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
    final next = job.nextRun;
    final last = job.lastRun;
    final failed = job.lastWentWell == false;
    final when = failed
        ? ['Last run failed', if (last != null) whenText(last, now)].join(' ')
        : !job.enabled
        ? 'Off'
        : next != null
        ? 'Next: ${whenText(next, now)}'
        : null;
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
              style: failed ? Type.sans(13, color: t.badfg) : null,
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
class _NoTasks extends StatelessWidget {
  const _NoTasks({required this.writable});

  /// Whether tasks can be made here, which adds a New task button.
  final bool writable;

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
              color: t.accentbg,
              shape: BoxShape.circle,
            ),
            child: AppIcon('clock', size: IconSize.large, color: t.accent),
          ),
          const SizedBox(height: 4),
          Text(
            'No scheduled tasks',
            textAlign: TextAlign.center,
            style: Type.sans(19, weight: FontWeight.w500, color: t.ink),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              writable
                  ? 'A task runs on a schedule, such as a summary every morning. '
                        'Make one here, or ask the agent to.'
                  : 'Nothing is scheduled on your server.',
              textAlign: TextAlign.center,
              style: Type.sans(14.5, color: t.muted, height: 1.5),
            ),
          ),
          if (writable) ...[
            const SizedBox(height: 8),
            AppButton(
              'New task',
              primary: true,
              leading: 'plus',
              onPressed: () => openTask(scope, const TaskSheet()),
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
