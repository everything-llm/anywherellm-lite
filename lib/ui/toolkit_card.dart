import 'package:flutter/material.dart';

import '../core/activity.dart';
import '../core/copy.dart';
import '../core/schedule.dart';
import 'app_scope.dart';
import 'settings/rows.dart';
import 'state/shell_controller.dart';
import 'state/toolkit_controller.dart';
import 'widgets/phone_page.dart';

/// What the toolkit adds to the shelf, a card under a 20 px gap with a row for each thing it
/// serves: Library, Activity and Upcoming, each with a line of what is in it once read, which a
/// tap opens as a page over the tab. It reads each the first time it shows on a server, and shows
/// nothing while the toolkit serves none.
class ToolkitCard extends StatefulWidget {
  const ToolkitCard({super.key});

  @override
  State<ToolkitCard> createState() => _ToolkitCardState();
}

class _ToolkitCardState extends State<ToolkitCard> {
  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.toolkit, scope.chat]),
      builder: (context, _) {
        final toolkit = scope.toolkit;
        // A read tells the controller's listeners at once, so it waits for the frame.
        if (toolkit.wants) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) toolkit.want();
          });
        }
        final rows = [
          if (toolkit.libraryServed)
            NavRow(
              icon: 'grid',
              title: 'Library',
              about: _library(toolkit, scope.chat.activeSlug),
              onTap: () => scope.shell.openToolkitPage(ToolkitPage.library),
            ),
          if (toolkit.activityServed)
            NavRow(
              icon: 'pulse',
              title: 'Activity',
              about: _activity(toolkit),
              onTap: () => scope.shell.openToolkitPage(ToolkitPage.activity),
            ),
          if (toolkit.jobsServed)
            NavRow(
              icon: 'clock',
              title: 'Upcoming',
              about: _upcoming(toolkit),
              onTap: () => scope.shell.openToolkitPage(ToolkitPage.upcoming),
            ),
        ];
        if (rows.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: FieldCard(rows),
        );
      },
    );
  }

  /// How many apps and files the open workspace has, or null until read.
  static String? _library(ToolkitController toolkit, String? slug) {
    final contents = toolkit.library;
    if (contents == null) return null;
    final apps = contents.apps.where((a) => a.isIn(slug)).length;
    final files = contents.files.where((f) => f.isIn(slug)).length;
    return apps + files == 0
        ? 'Nothing yet'
        : '${plural(apps, 'app', 'apps')} · ${plural(files, 'file', 'files')}';
  }

  /// What went wrong or what happened today, or null until read.
  static String? _activity(ToolkitController toolkit) {
    final events = toolkit.activity;
    if (events == null) return null;
    final now = DateTime.now();
    final today = [
      for (final e in events)
        if (calendarDays(e.at.toLocal(), now) == 0) e,
    ];
    final failed = today
        .where((e) => e.outcome == ActivityOutcome.failed)
        .length;
    if (failed > 0) return '$failed failed today';
    return today.isEmpty ? 'Nothing today' : '${today.length} today';
  }

  /// How many jobs there are and when the next runs, or null until read. They are tasks where
  /// the toolkit lets them be changed.
  static String? _upcoming(ToolkitController toolkit) {
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
}
