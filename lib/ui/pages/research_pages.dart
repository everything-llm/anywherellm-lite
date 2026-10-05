import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/list_filter.dart';
import '../../core/models.dart';
import '../app_scope.dart';
import '../state/nav_controller.dart';
import '../widgets/basics.dart';
import '../widgets/rows.dart';
import 'library_list.dart';
import 'page_frame.dart';

class ResearchListPage extends StatelessWidget {
  const ResearchListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return LibraryList<ResearchEntry>(
      library: 'research',
      title: 'Research',
      sub: 'AI-collected documents. Open one to read it and see how far to trust it.',
      noun: 'documents',
      load: scope.api.research,
      facts: (d) => Facts(
        text: '${stem(d.path)} ${d.meta.summary}',
        facet: d.meta.kind,
        tags: d.meta.tags,
      ),
      group: (d) => areaOf(d.path),
      searchHint: 'Search research',
      facetLabel: 'Filter by type',
      allFacets: 'All types',
      emptyTitle: 'No research yet',
      emptyText: 'Stage a markdown file in the Inbox, then file it with nils chat or nils research add.',
      row: (context, d, corners, filter) => NilsRow(
        title: stem(d.path),
        meta: d.meta.summary,
        badges: [
          NilsBadge(BadgeSpec(d.meta.kind)),
          // Only what needs a second look: the good values say nothing a person acts on.
          if (d.meta.status != 'current') NilsBadge(statusBadge(d.meta.status)),
          if (d.meta.verified == 'none')
            NilsBadge(verifiedBadge(d.meta.verified)),
          for (final tag in d.meta.tags) tagBadge(tag, filter),
        ],
        radius: corners,
        onTap: () => scope.nav.go(ResearchDocRoute(d.path)),
      ),
    );
  }
}

class ResearchDocPage extends StatelessWidget {
  const ResearchDocPage(this.path, {super.key});

  final String path;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return LoadPage<ResearchDoc>(
      load: () => scope.api.researchDoc(path),
      builder: (context, doc) {
        final parts = path.split('/');
        final meta = doc.meta;
        final crumb = Crumb([
          CrumbPart(
            'Research',
            onTap: () => scope.nav.go(const ResearchListRoute()),
          ),
          if (parts.length > 1)
            CrumbPart(parts.sublist(0, parts.length - 1).join(' / ')),
        ]);
        final trust = meta == null ? null : researchTrustWarning(meta);
        return [
          PageHead(stem(path), sub: meta?.summary, crumb: crumb),
          if (meta == null)
            const FrontMatterAlert('research')
          else ...[
            if (trust != null)
              AlertBox(
                AlertKind.warn,
                'Say so before relying on this',
                text: trust,
              ),
            KvCard([
              Kv('Type', text: meta.kind),
              Kv('Status', child: NilsBadge(statusBadge(meta.status))),
              Kv('Verified', child: NilsBadge(verifiedBadge(meta.verified))),
              Kv('Date', text: meta.date),
              Kv('Produced by', text: meta.producedBy),
              tagsKv(meta.tags),
              Kv(
                'Sources',
                text: '${meta.sources.length} link(s)',
                rule: KvRule.none,
              ),
            ]),
          ],
          CodeBlock(doc.text, long: true),
        ];
      },
    );
  }
}
