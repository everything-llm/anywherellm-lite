import 'dart:async';

import 'package:flutter/material.dart';

import '../core/copy.dart';
import '../core/schedule.dart';
import 'app_scope.dart';
import 'links.dart';
import 'settings/settings_pages.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/basics.dart';
import 'widgets/buttons.dart';
import 'widgets/drawer_row.dart';
import 'widgets/phone_page.dart';
import 'widgets/fields.dart';

/// Upcoming in a phone's drawer: the jobs the server runs on a schedule, with how many once
/// read. It reads them the first time it shows on a server. Tapped, it opens [UpcomingPage].
class UpcomingRow extends StatefulWidget {
  const UpcomingRow({super.key});

  @override
  State<UpcomingRow> createState() => _UpcomingRowState();
}

class _UpcomingRowState extends State<UpcomingRow> {
  @override
  void initState() {
    super.initState();
    final system = AppScope.of(context).system;
    // A read tells the controller's listeners at once, so it waits for the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && system.jobs == null && system.jobsProblem == null) {
        unawaited(system.readJobs());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: scope.system,
      builder: (context, _) {
        final jobs = scope.system.jobs;
        final count = jobs == null ? null : plural(jobs.length, 'job', 'jobs');
        return DrawerRow(
          icon: 'clock',
          title: 'Upcoming',
          heard: count == null ? 'Upcoming' : 'Upcoming, $count',
          trailing: count == null
              ? null
              : Text(count, style: Type.sans(12.5, color: t.muted)),
          onTap: () {
            scope.shell
              ..closeSide()
              ..openUpcoming();
          },
        );
      },
    );
  }
}

/// A phone's Upcoming: each job the server runs on a schedule, read only, with its workspace,
/// its schedule in local time, when it runs next and how its last run went, then a way to
/// AnythingLLM's web page to change them. It reads the jobs afresh as it opens. A server with a
/// password needs it saved for this.
class UpcomingPage extends StatefulWidget {
  const UpcomingPage({super.key});

  @override
  State<UpcomingPage> createState() => _UpcomingPageState();
}

class _UpcomingPageState extends State<UpcomingPage> {
  @override
  void initState() {
    super.initState();
    final system = AppScope.of(context).system;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(system.readJobs());
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final shell = scope.shell;
    return ColoredBox(
      color: t.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhonePageHeader(
            title: 'Upcoming',
            back: 'Back to the chat',
            onBack: shell.closeUpcoming,
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: scope.system,
              builder: (context, _) {
                final system = scope.system;
                final jobs = system.jobs;
                final now = DateTime.now();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  children: [
                    Text(
                      'Jobs the server runs on a schedule.',
                      style: Type.sans(14.5, color: t.ink2),
                    ),
                    const SizedBox(height: 14),
                    if (system.jobsProblem case final problem?) ...[
                      AlertBox(
                        AlertKind.warn,
                        problem.title,
                        text: problem.text,
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppButton(
                          'Open Connection',
                          onPressed: () {
                            shell
                              ..closeUpcoming()
                              ..openSettings(SettingsPage.connection);
                          },
                        ),
                      ),
                    ] else if (jobs == null)
                      Text('Reading…', style: Type.sans(14, color: t.muted))
                    else if (jobs.isEmpty)
                      Text(
                        'No scheduled jobs.',
                        style: Type.sans(14, color: t.muted),
                      )
                    else
                      for (final job in jobs) ...[
                        _JobCard(job, now: now),
                        const SizedBox(height: 8),
                      ],
                    const SizedBox(height: 12),
                    if (scope.settings.configured)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppButton(
                          'Edit in AnythingLLM\'s web page',
                          onPressed: () => openServerPage(context),
                        ),
                      ),
                    const SizedBox(height: 10),
                    const HelpText(
                      'Read only here. A job\'s result goes to its workspace.',
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One job: its name, its workspace and schedule, then when it runs next and how it last ran.
class _JobCard extends StatelessWidget {
  const _JobCard(this.job, {required this.now});

  final ScheduledJob job;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final next = job.nextRun;
    final last = job.lastRun;
    final lines = [
      if (!job.enabled)
        'Off'
      else if (next != null)
        'Next: ${whenText(next, now)}',
      if (last != null)
        'Last run: ${[?job.lastStatus, whenText(last, now)].join(', ')}',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: t.panel,
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          Text(
            job.name,
            style: Type.sans(15.5, weight: FontWeight.w500, color: t.ink),
          ),
          Text(
            [?job.workspace, describeSchedule(job.cron, now)].join(' · '),
            style: Type.sans(12.5, color: t.muted),
          ),
          for (final line in lines)
            Text(line, style: Type.sans(13, color: t.ink2)),
        ],
      ),
    );
  }
}
