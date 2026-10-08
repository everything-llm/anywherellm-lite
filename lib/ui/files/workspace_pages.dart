import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../../core/copy.dart';
import '../../core/files.dart';
import '../app_scope.dart';
import '../layout.dart';
import '../state/files_controller.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/min_height.dart';
import '../widgets/phone_page.dart';
import 'files_view.dart';
import '../settings/rows.dart';
import '../widgets/fields.dart';

/// Files on a phone: the open workspace's pages rather than the server's tree. It opens on the
/// list of them, Documents, Instructions and Answer settings, each with a line of what it
/// holds; a page opens under a back arrow, and the text of a document over that. Created files
/// and the tree stay on the desktop.
class WorkspacePages extends StatefulWidget {
  const WorkspacePages({super.key});

  @override
  State<WorkspacePages> createState() => _WorkspacePagesState();
}

class _WorkspacePagesState extends State<WorkspacePages> {
  late final FilesController _files;

  @override
  void initState() {
    super.initState();
    _files = AppScope.of(context).files;
    if (!_files.essentials) _files.showEssentials(true);
    // Loading notifies, which must wait until the frame that builds the pages is done.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _files.ensureLoaded();
    });
  }

  @override
  void dispose() {
    _files.hidden();
    super.dispose();
  }

  /// Opens [section]'s page.
  void _open(ShellController shell, FilesSection section) {
    shell.showWorkspacePage(section);
    _files.openSection(section);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    return ListenableBuilder(
      listenable: Listenable.merge([_files, shell, scope.chat]),
      builder: (context, _) {
        final workspace = scope.chat.active;
        final reading = _files.reading;
        final page = shell.workspacePage;
        final name = workspace?.name ?? 'Workspace';
        final (title, back, onBack) = reading != null
            ? (
                reading.title,
                page == null ? 'Back to $name' : 'Back to ${page.title}',
                _files.closeText,
              )
            : page != null
            ? (page.title, 'Back to $name', () => shell.showWorkspacePage(null))
            : (name, 'Back to the chat', () => shell.showPane(Pane.chats));
        final node = _files.node;
        return MinHeight(
          min: Sizes.panelMin,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PhonePageHeader(title: title, back: back, onBack: onBack),
              for (final problem in _files.problems)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: AlertBox(
                    AlertKind.bad,
                    problem.title,
                    text: problem.text,
                  ),
                ),
              Expanded(
                child: workspace == null
                    ? const Blank('No workspace is open.')
                    : reading != null || page != null
                    ? essentialSection(context, node, phone: true)
                    : _overview(context, workspace.name),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The list of the workspace's pages, each with what it holds.
  Widget _overview(BuildContext context, String name) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final shell = scope.shell;
    return ListenableBuilder(
      listenable: Listenable.merge([scope.sources, scope.system]),
      builder: (context, _) {
        final docs = scope.sources.files;
        final on = docs.where((f) => f.on).length;
        final prompt = _files
            .detail(scope.chat.activeSlug ?? '')
            ?.prompt
            ?.trim()
            .split('\n')
            .first;
        final mode = scope.sources.chatMode.value;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Text(
              'What this workspace answers from, and how.',
              style: Type.sans(14.5, color: t.ink2),
            ),
            const SizedBox(height: 14),
            FieldCard([
              NavRow(
                title: 'Documents',
                about: docs.isEmpty
                    ? 'None yet'
                    : '${plural(docs.length, 'document', 'documents')}, '
                          '$on used in answers',
                onTap: () => _open(shell, FilesSection.documents),
              ),
              NavRow(
                title: 'Instructions',
                about: prompt == null || prompt.isEmpty
                    ? 'The server\'s default'
                    : prompt,
                onTap: () => _open(shell, FilesSection.instructions),
              ),
              NavRow(
                title: 'Answer settings',
                about: [
                  mode?.title ?? ChatMode.automatic.title,
                  if (scope.sources.chatModel case final own?)
                    own
                  else
                    'system model',
                ].join(' · '),
                onTap: () => _open(shell, FilesSection.answers),
              ),
            ]),
            const SizedBox(height: 12),
            const HelpText(
              'Created files and the file tree are in the desktop app.',
            ),
          ],
        );
      },
    );
  }
}
