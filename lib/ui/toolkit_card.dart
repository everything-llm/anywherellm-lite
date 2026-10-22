import 'dart:async';

import 'package:flutter/material.dart';

import '../core/copy.dart';
import '../core/ports.dart';
import '../core/schedule.dart';
import '../core/skill_pages.dart';
import 'app_scope.dart';
import 'links.dart';
import 'settings/rows.dart';
import 'state/shell_controller.dart';
import 'state/toolkit_controller.dart';
import 'widgets/phone_page.dart';

/// What the toolkit adds to the shelf, a card under a 20 px gap with a row for each thing it
/// serves: the suite's Library and Vault pages that are set up, then Upcoming, with a line of
/// what is in it once read, which a tap opens as a page over the chat. It reads the jobs the
/// first time it shows on a server, and which pages are set up each time it opens. A page's row reads where the page is afresh at the tap, opens it, and closes the shelf
/// once the read is back, so the page or the notice shows; the page's address is never kept. It
/// shows nothing while the toolkit serves none.
class ToolkitCard extends StatefulWidget {
  const ToolkitCard({super.key});

  @override
  State<ToolkitCard> createState() => _ToolkitCardState();
}

class _ToolkitCardState extends State<ToolkitCard> {
  @override
  void initState() {
    super.initState();
    AppScope.of(context).toolkit.wantPages();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.toolkit, scope.chat]),
      builder: (context, _) {
        final toolkit = scope.toolkit;
        toolkit.want();
        final rows = [
          if (toolkit.pagesServed)
            for (final page in SkillPage.values)
              if (page.listing case final listing?
                  when toolkit.pagesFound.contains(page))
                NavRow(
                  icon: page == SkillPage.vault ? 'shield' : 'grid',
                  title: listing.title,
                  about: listing.about,
                  onTap: () => _open(page, listing.title),
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

  /// Opens [page], named [title], at the address the toolkit gives now, on the connected
  /// server. A failure, or a page not set up, shows as a notice in the chat. The shelf closes
  /// after the read, so what opened shows, and the address is held by this call alone.
  Future<void> _open(SkillPage page, String title) async {
    final scope = AppScope.of(context);
    try {
      final path = await scope.toolkit.pagePath(page);
      if (!mounted) return;
      final server = scope.settings.connection?.uri;
      if (path == null || server == null) {
        scope.chat.reportLink(
          'The $title is not set up yet',
          'Ask the agent to open the $title in a chat, then try again.',
        );
      } else {
        // The shelf holds this card: it opens first, since it needs the card's context.
        unawaited(openSkillPage(context, page, server.resolve(path)));
      }
    } on ApiException catch (error) {
      scope.chat.reportLink('Could not open the $title', error.message);
    }
    scope.shell.closeShelf();
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
