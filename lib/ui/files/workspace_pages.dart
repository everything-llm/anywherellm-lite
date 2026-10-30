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
import 'section_view.dart';
import '../settings/rows.dart';
import '../widgets/scroll_fades.dart';

/// What the page of [section] is called: Answer settings is Answer from.
String _titleOf(FilesSection section) =>
    section == FilesSection.answers ? 'Answer from' : section.title;

/// The open workspace's pages, which [Pane.files] shows. They open on the workspace, with Rename and Delete workspace, and its Documents, Instructions and Answer
/// from, each with a line of what it holds; a page opens under a back arrow.
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
    _files = AppScope.of(context).files..shown();
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
        final page = shell.workspacePage;
        final (title, back, onBack) = page != null
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
        // A page draws this itself, so the instructions can put their buttons in it.
        Widget top(Widget? action) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PhonePageHeader(
              title: title,
              back: back,
              onBack: onBack,
              action: action,
            ),
            for (final problem in _files.problems)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: AlertBox.notice(AlertKind.bad, problem),
              ),
          ],
        );
        return MinHeight(
          min: Sizes.panelMin,
          child: page != null
              ? workspaceSection(context, top: top)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    top(null),
                    Expanded(
                      child: ScrollFades(
                        child: workspace == null
                            ? const Blank('No workspace is open.')
                            : _overview(context, workspace.name),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  /// The workspace's settings: its name with its chats and documents, and Rename; then How it
  /// answers, its Documents, Instructions and Answer from, each with what it holds; then Delete
  /// workspace.
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
        final prompt = _files.detail(slug)?.prompt?.trim();
        final mode = scope.sources.chatMode.value;
        return ListView(
          padding: Sizes.pageIn(context),
          children: [
            SummaryCard(
              title: name,
              trailing: Text(
                plural(chats, 'chat', 'chats'),
                style: Type.note(t.ink),
              ),
              lines: [
                Text(
                  docs.isEmpty
                      ? 'No documents yet'
                      : '${plural(docs.length, 'document', 'documents')}, '
                            '$on used in answers',
                  style: Type.note(t.ink),
                ),
              ],
              link: 'Rename',
              onLink: () => shell.togglePopup(WorkspaceSheet.rename),
            ),
            const CardHeading('How it answers'),
            FieldCard([
              NavRow(
                icon: 'doc',
                title: 'Documents',
                about: docs.isEmpty
                    ? 'None yet'
                    : '$on of ${docs.length} used in answers',
                onTap: () => shell.openSources(asPane: Wide.split(context)),
              ),
              NavRow(
                icon: 'pencil',
                title: 'Instructions',
                about: prompt == null || prompt.isEmpty
                    ? 'The server\'s default'
                    : promptPreview(prompt),
                onTap: () => _open(shell, FilesSection.instructions),
              ),
              NavRow(
                icon: 'settings',
                title: 'Answer from',
                about: (mode ?? ChatMode.automatic).title,
                onTap: () => _open(shell, FilesSection.answers),
              ),
            ]),
            const SizedBox(height: 20),
            FieldCard([
              CardRow(
                'Delete workspace',
                icon: 'trash',
                tone: RowTone.danger,
                large: true,
                onTap: chat.activeIdle
                    ? () => shell.togglePopup(WorkspaceSheet.delete)
                    : null,
              ),
            ]),
          ],
        );
      },
    );
  }
}
