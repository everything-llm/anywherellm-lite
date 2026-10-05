import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/server_models.dart';
import '../app_scope.dart';
import '../state/nav_controller.dart';
import '../widgets/basics.dart';
import '../widgets/rows.dart';
import 'page_frame.dart';

/// `my-space, 2 threads`: what a workspace row says under its name.
String _summary(Workspace workspace) => [
  workspace.slug,
  ?workspace.chatModel,
  plural(workspace.threads, 'thread', 'threads'),
].join(', ');

class WorkspacesPage extends StatelessWidget {
  const WorkspacesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return LoadPage<List<Workspace>>(
      load: scope.llm.workspaces,
      builder: (context, workspaces) => [
        const PageHead(
          'Workspaces',
          sub: 'Each workspace chats over the documents added to it.',
        ),
        if (workspaces.isEmpty)
          const EmptyState(
            'No workspaces yet',
            'Create a workspace in AnythingLLM, then it shows here.',
          )
        else
          NilsList([
            for (final workspace in workspaces)
              NilsRow(
                title: workspace.name,
                meta: _summary(workspace),
                onTap: () => scope.nav.go(WorkspaceRoute(workspace.slug)),
              ),
          ]),
      ],
    );
  }
}

class WorkspacePage extends StatelessWidget {
  const WorkspacePage(this.slug, {super.key});

  final String slug;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return LoadPage<Workspace>(
      load: () => scope.llm.workspace(slug),
      builder: (context, workspace) => [
        PageHead(
          workspace.name,
          crumb: Crumb([
            CrumbPart(
              'Workspaces',
              onTap: () => scope.nav.go(const WorkspacesRoute()),
            ),
          ]),
        ),
        KvCard([
          Kv('Slug', text: workspace.slug),
          Kv('Chat model', text: workspace.chatModel ?? 'the server default'),
          Kv('Threads', text: '${workspace.threads}', rule: KvRule.none),
        ]),
        if (workspace.documents.isEmpty)
          const EmptyState(
            'No documents in this workspace',
            'Add documents to it in AnythingLLM.',
          )
        else
          ListSection(
            plural(workspace.documents.length, 'document', 'documents'),
            [
              for (final doc in workspace.documents)
                NilsRow(
                  title: doc.title,
                  meta: doc.path,
                  monoMeta: true,
                  onTap: () => scope.nav.go(DocumentRoute(doc.path)),
                ),
            ],
          ),
      ],
    );
  }
}
