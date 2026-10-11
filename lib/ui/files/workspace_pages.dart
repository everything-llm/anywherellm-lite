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
import '../icons.dart';
import '../widgets/basics.dart';
import '../widgets/tappable.dart';
import '../widgets/min_height.dart';
import '../widgets/phone_page.dart';
import 'files_view.dart';
import '../settings/rows.dart';
import '../widgets/fields.dart';

/// What a phone calls the page of [section]: Answer settings is Answer from.
String _titleOf(FilesSection section) =>
    section == FilesSection.answers ? 'Answer from' : section.title;

/// Files on a phone: the open workspace's settings rather than the server's tree. It opens on
/// the workspace, with Rename and Delete workspace, and its Documents, Instructions and Answer
/// from, each with a line of what it holds; a page opens under a back arrow, and the text of a
/// document over that. Created files and the tree stay on the desktop.
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
        final (title, back, onBack) = reading != null
            ? (
                reading.title,
                page == null
                    ? 'Back to the workspace'
                    : 'Back to ${_titleOf(page)}',
                _files.closeText,
              )
            : page != null
            ? (
                _titleOf(page),
                'Back to the workspace',
                () => shell.showWorkspacePage(null),
              )
            : (
                'Workspace',
                'Back to the chat',
                () => shell.showPane(Pane.chats),
              );
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

  /// The workspace's settings: its name with its chats and documents, and Rename; then How it
  /// answers, its Documents, Instructions and Answer from, each with what it holds; then
  /// Delete workspace.
  Widget _overview(BuildContext context, String name) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final shell = scope.shell;
    final chat = scope.chat;
    return ListenableBuilder(
      listenable: Listenable.merge([scope.sources, scope.system]),
      builder: (context, _) {
        final slug = chat.activeSlug ?? '';
        final docs = scope.sources.files;
        final on = docs.where((f) => f.on).length;
        final chats = chat.threadsOf(slug).length;
        final prompt = _files.detail(slug)?.prompt?.trim().split('\n').first;
        final mode = scope.sources.chatMode.value;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            FieldCard([
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FieldCard.inset,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Row(
                      spacing: 12,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Type.sans(
                              19,
                              weight: FontWeight.w500,
                              color: t.ink,
                            ),
                          ),
                        ),
                        Text(
                          plural(chats, 'chat', 'chats'),
                          style: Type.sans(13, color: t.muted),
                        ),
                      ],
                    ),
                    Text(
                      '${plural(docs.length, 'document', 'documents')}, '
                      '$on used in answers',
                      style: Type.sans(13, color: t.muted),
                    ),
                  ],
                ),
              ),
              Tappable(
                label: 'Rename',
                onTap: () => shell.togglePopup(WorkspaceSheet.rename),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(
                    horizontal: FieldCard.inset,
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Rename',
                    style: Type.sans(
                      17,
                      weight: FontWeight.w500,
                      color: t.accent,
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: FieldCard.inset),
              child: SectionLabel('How it answers'),
            ),
            const SizedBox(height: 8),
            FieldCard([
              NavRow(
                icon: 'doc',
                title: 'Documents',
                about: docs.isEmpty
                    ? 'None yet'
                    : '$on of ${docs.length} used in answers',
                onTap: () => _open(shell, FilesSection.documents),
              ),
              NavRow(
                icon: 'pencil',
                title: 'Instructions',
                about: prompt == null || prompt.isEmpty
                    ? 'The server\'s default'
                    : prompt,
                onTap: () => _open(shell, FilesSection.instructions),
              ),
              NavRow(
                icon: 'chat',
                title: 'Answer from',
                about: (mode ?? ChatMode.automatic).title,
                onTap: () => _open(shell, FilesSection.answers),
              ),
            ]),
            const SizedBox(height: 20),
            FieldCard([
              Tappable(
                label: 'Delete workspace',
                onTap: chat.answeringIn(slug)
                    ? null
                    : () => shell.togglePopup(WorkspaceSheet.delete),
                dimWhenDisabled: 0.5,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 64),
                  padding: const EdgeInsets.symmetric(
                    horizontal: FieldCard.inset,
                  ),
                  child: Row(
                    spacing: 16,
                    children: [
                      AppIcon('trash', color: t.badfg),
                      Flexible(
                        child: Text(
                          'Delete workspace',
                          style: Type.sans(17, color: t.badfg),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: HelpText(
                'Created files and the file tree are in the desktop app.',
              ),
            ),
          ],
        );
      },
    );
  }
}
