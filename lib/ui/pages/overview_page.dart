import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/models.dart';
import '../app_scope.dart';
import '../state/nav_controller.dart';
import '../widgets/basics.dart';
import '../widgets/findings.dart';
import '../widgets/rows.dart';
import 'page_frame.dart';

/// What the libraries hold, what their last check found, and where nils keeps things. It
/// shows what the app already knows and asks again when it opens.
class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  @override
  void initState() {
    super.initState();
    AppScope.of(context).overview.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.overview,
      builder: (context, _) {
        final overview = scope.overview.data;
        final places = overview.locations;
        return PageFrame(
          children: [
            const PageHead(
              'Overview',
              sub: 'What the libraries hold and where nils keeps things.',
            ),
            ListSection('Libraries', [
              _LibraryRow(
                title: 'Research',
                counts: overview.research,
                noun: ('document', 'documents'),
                onTap: () => scope.nav.go(const ResearchListRoute()),
              ),
              _LibraryRow(
                title: 'Skills',
                counts: overview.skills,
                noun: ('skill', 'skills'),
                onTap: () => scope.nav.go(const SkillsListRoute()),
              ),
            ]),
            if (overview.findings.isNotEmpty)
              FindingsSection(overview.findings, showLibrary: true),
            ListSection('Where nils keeps things', [
              for (final (title, path) in [
                ('Research folder', places.researchRoot),
                ('Skills folder', places.skillsRoot),
                ('Inbox', places.inbox),
                ('Opening prompt', places.prompt),
              ])
                if (path.isNotEmpty)
                  NilsRow(title: title, meta: path, monoMeta: true),
            ]),
          ],
        );
      },
    );
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.title,
    required this.counts,
    required this.noun,
    required this.onTap,
  });

  final String title;
  final LibraryCounts counts;
  final (String, String) noun;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => NilsRow(
    title: title,
    meta: countsLine(counts, noun.$1, noun.$2),
    badges: [for (final spec in checkBadges(counts)) NilsBadge(spec)],
    onTap: onTap,
  );
}
