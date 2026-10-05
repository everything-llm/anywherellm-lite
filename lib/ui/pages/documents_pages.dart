import 'package:flutter/material.dart';

import '../../core/documents.dart';
import '../../core/list_filter.dart';
import '../../core/server_models.dart';
import '../app_scope.dart';
import '../state/nav_controller.dart';
import '../widgets/basics.dart';
import '../widgets/fields.dart';
import '../widgets/rows.dart';
import 'library_list.dart';
import 'page_frame.dart';

class DocumentsPage extends StatelessWidget {
  const DocumentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return LibraryList<DocEntry>(
      title: 'Documents',
      sub: 'Everything the server has read in, by folder. Open one to see which workspaces hold it.',
      noun: 'documents',
      load: () async => [
        for (final folder in await scope.llm.documents()) ...folder.docs,
      ],
      facts: (d) => Facts(
        text: '${d.title} ${d.description ?? ''} ${d.name}',
        facet: d.folder,
      ),
      group: (d) => d.folder,
      searchHint: 'Search documents',
      facetLabel: 'Filter by folder',
      allFacets: 'All folders',
      emptyTitle: 'No documents yet',
      emptyText: 'Upload a file and it shows here.',
      row: (context, d, corners) => NilsRow(
        title: d.title,
        meta: d.description ?? d.source,
        radius: corners,
        onTap: () => scope.nav.go(DocumentRoute(d.path)),
      ),
    );
  }
}

class DocumentPage extends StatelessWidget {
  const DocumentPage(this.path, {super.key});

  final String path;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return LoadPage<DocumentView>(
      load: () => openDocument(scope.llm, path),
      builder: (context, view) {
        final doc = view.doc;
        final facts = [
          ('File', doc.name),
          ('Folder', doc.folder),
          ('Author', doc.author),
          ('Source', doc.source),
          ('Published', doc.published),
          ('Words', doc.words?.toString()),
          ('Tokens, estimated', doc.tokens?.toString()),
        ].where((fact) => fact.$2 != null).toList();
        return [
          PageHead(
            doc.title,
            sub: doc.description,
            crumb: Crumb([
              CrumbPart(
                'Documents',
                onTap: () => scope.nav.go(const DocumentsRoute()),
              ),
              CrumbPart(doc.folder),
            ]),
          ),
          KvCard([
            for (final (i, (label, value)) in facts.indexed)
              Kv(
                label,
                text: value,
                rule: i == facts.length - 1 ? KvRule.none : KvRule.bottom,
              ),
          ]),
          if (view.holders.isEmpty)
            const EmptyState(
              'In no workspace',
              'Add it to a workspace in AnythingLLM to chat over it.',
            )
          else
            ListSection('In workspaces', [
              for (final workspace in view.holders)
                NilsRow(
                  title: workspace.name,
                  meta: workspace.slug,
                  onTap: () => scope.nav.go(WorkspaceRoute(workspace.slug)),
                ),
            ]),
          const HelpText(
            'AnythingLLM\'s API does not return a document\'s text, so it is not shown here.',
          ),
        ];
      },
    );
  }
}
