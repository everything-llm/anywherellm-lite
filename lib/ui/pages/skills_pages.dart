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

String _topic(SkillMeta skill) => skill.topic ?? unclassified;

class SkillsListPage extends StatelessWidget {
  const SkillsListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return LibraryList<SkillMeta>(
      library: 'skills',
      title: 'Skills',
      sub: 'Agent skills in the Cline SKILL.md format, grouped by topic.',
      noun: 'skills',
      load: scope.api.skills,
      facts: (s) => Facts(
        text: '${s.name} ${s.description}',
        facet: _topic(s),
        tags: s.tags,
      ),
      group: _topic,
      searchHint: 'Search skills',
      facetLabel: 'Filter by topic',
      allFacets: 'All topics',
      emptyTitle: 'No skills yet',
      emptyText: 'Copy a skill directory into storage/inbox, then file it with nils chat or nils skills add.',
      row: (context, s, corners, filter) => NilsRow(
        title: s.name,
        mono: true,
        meta: s.description,
        badges: [for (final tag in s.tags) tagBadge(tag, filter)],
        radius: corners,
        onTap: () => scope.nav.go(SkillDocRoute(s.name)),
      ),
    );
  }
}

class SkillDocPage extends StatelessWidget {
  const SkillDocPage(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return LoadPage<SkillDoc>(
      load: () => scope.api.skillDoc(name),
      builder: (context, doc) {
        final meta = doc.meta;
        return [
          PageHead(
            name,
            mono: true,
            sub: meta?.description,
            crumb: Crumb([
              CrumbPart(
                'Skills',
                onTap: () => scope.nav.go(const SkillsListRoute()),
              ),
            ]),
          ),
          if (meta == null)
            const FrontMatterAlert('skills')
          else
            KvCard([
              Kv(
                'Topic',
                child: meta.topic == null
                    ? const Text(unclassified)
                    : NilsBadge(BadgeSpec(meta.topic!, BadgeKind.accent)),
              ),
              tagsKv(meta.tags),
              Kv('Added', text: meta.added ?? 'unknown', rule: KvRule.none),
            ]),
          CodeBlock(doc.text, long: true),
        ];
      },
    );
  }
}
