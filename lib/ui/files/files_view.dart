import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/files.dart';
import '../app_scope.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/min_height.dart';
import '../widgets/pane_header.dart';
import 'doc_views.dart';
import 'essentials.dart';
import 'file_tree.dart';
import 'folder_view.dart';
import 'settings_form.dart';

/// The node picked in the file tree: a folder's contents and actions, a file's text, an editor
/// for a workspace's prompt and settings, or a document. In the Essentials view, the open
/// workspace's section picked in the sidebar, or the text of one of its documents.
class FilesView extends StatelessWidget {
  const FilesView({super.key, required this.showMenu});

  /// Whether the header has a button to open the sidebar drawer.
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final files = scope.files;
    return ListenableBuilder(
      listenable: Listenable.merge([files, scope.settings]),
      builder: (context, _) {
        final node = files.node;
        final essentials = files.essentials && scope.settings.configured;
        // Short, as with the keyboard up, the whole pane scrolls: the header and problems
        // as well as the open file.
        return MinHeight(
          min: Sizes.panelMin,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PaneHeader(
                showMenu: showMenu,
                onMenu: scope.shell.toggleSide,
                title: Text(
                  essentials
                      ? files.reading?.title ?? files.section.title
                      : node == null
                      ? 'Files'
                      : node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PaneHeader.titleStyle(context),
                ),
                actions: switch (node == null || essentials
                    ? null
                    : badgeText(node.badge)) {
                  final text? => (_) => [
                    const SizedBox(width: 12),
                    AppBadge(text, kind: BadgeKind.warn),
                  ],
                  null => null,
                },
              ),
              for (final problem in files.problems)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: AlertBox(
                    AlertKind.bad,
                    problem.title,
                    text: problem.text,
                  ),
                ),
              Expanded(
                child: essentials
                    ? essentialSection(context, node)
                    : _body(context, node),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, FileNode? node) {
    final scope = AppScope.of(context);
    final files = scope.files;
    if (!scope.settings.configured) {
      return const Blank(
        'Sign in to your AnythingLLM server in Settings to begin.',
      );
    }
    if (node == null) {
      return Blank(
        files.loading ? 'Loading…' : 'Pick a folder or a file on the left.',
      );
    }
    // Keyed by path, so a file waiting to be added or an open Delete stays with its folder.
    if (node.kind.isFolder) return FolderView(node, key: ValueKey(node.path));
    if (files.contentLoading) return const Blank('Loading…');
    return switch (node.kind) {
      NodeKind.locked => const Blank(
        'Locked. AnywhereLLM never reads this: it holds keys and secrets.',
      ),
      NodeKind.prompt => _Editor(
        key: ValueKey('${node.path}#${files.revision}'),
        node: node,
      ),
      NodeKind.settings => _SettingsPage(
        key: ValueKey('${node.path}#${files.revision}'),
        node: node,
      ),
      // Keyed by path, so a question asked about one document never carries to the next.
      NodeKind.libraryDoc => LibraryDocView(node, key: ValueKey(node.path)),
      NodeKind.docLink => DocLinkView(node, key: ValueKey(node.path)),
      _ => TextPage(files.text ?? ''),
    };
  }
}

/// A line of muted text in the middle of the pane.
class Blank extends StatelessWidget {
  const Blank(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Type.sans(15, color: Tokens.of(context).muted),
      ),
    ),
  );
}

/// Read-only text in a monospace face, selectable.
class TextPage extends StatelessWidget {
  const TextPage(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: SelectableText(
      text,
      style: Type.mono(13, color: Tokens.of(context).ink, height: 1.5),
    ),
  );
}

/// A workspace's `settings.json`: the form, or the JSON itself when asked for. Its key changes
/// each time the settings are read afresh, which drops the draft.
class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    super.key,
    required this.node,
    this.plain = false,
    this.phone = false,
  });

  final FileNode node;

  /// Names the form's fields as the Essentials view does.
  final bool plain;

  /// Shows only what a phone does: Answer from, the model and the refusal.
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final files = AppScope.of(context).files;
    return files.settingsAsJson
        ? _Editor(node: node, onForm: () => files.showSettingsAsJson(false))
        : SettingsForm(
            slug: node.slug!,
            plain: plain,
            phone: phone,
            onJson: () => files.showSettingsAsJson(true),
          );
  }
}

/// The editor for a workspace's `PROMPT.md`, or for its `settings.json` as raw JSON. Its key
/// changes each time the text is read afresh, which drops the draft.
class _Editor extends StatefulWidget {
  const _Editor({super.key, required this.node, this.onForm});

  final FileNode node;

  /// Switches back to the form, for settings.
  final VoidCallback? onForm;

  @override
  State<_Editor> createState() => _EditorState();
}

/// The opening tag of the server's EverythingLLM block, with or without attributes.
final _everythingllmBlock = RegExp(r'<everythingllm[\s>]');

class _EditorState extends State<_Editor> {
  late final TextEditingController _draft;
  late final String _saved;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _saved = AppScope.of(context).files.text ?? '';
    _draft = TextEditingController(text: _saved);
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  bool get _dirty => _draft.text != _saved;

  Future<void> _save() async {
    if (!_dirty || _saving) return;
    setState(() => _saving = true);
    await AppScope.of(context).files.save(_draft.text);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final prompt = widget.node.kind == NodeKind.prompt;
    final notes = prompt
        ? [
            _saved.trim().isEmpty
                ? 'Empty: the server\'s default system prompt applies.'
                : 'This prompt replaces the default system prompt in this workspace.',
            if (_everythingllmBlock.hasMatch(_saved)) 'Write your own instructions outside the <everythingllm> block; the server\'s update-prompt skill replaces that block.',
          ]
        : [
            'null means the system default. chatMode is the workspace\'s chat mode: automatic (Agent), chat or query.',
          ];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.onForm case final onForm?)
              Align(
                alignment: Alignment.centerRight,
                child: TextAction('settings', 'Edit as a form', onForm),
              ),
            for (final note in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(note, style: Type.sans(13, color: t.muted)),
              ),
            const SizedBox(height: 6),
            Expanded(
              child: Semantics(
                label: widget.node.name,
                textField: true,
                child: TextField(
                  controller: _draft,
                  expands: true,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: Type.mono(13, color: t.ink, height: 1.5),
                  cursorColor: t.accent,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: t.panel,
                    contentPadding: const EdgeInsets.all(14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: t.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: t.accent, width: 2),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Only the buttons follow the draft, so typing rebuilds nothing else.
            ListenableBuilder(
              listenable: _draft,
              builder: (context, _) => ActionRow([
                AppButton(
                  'Revert',
                  onPressed: _dirty && !_saving
                      ? () => _draft.text = _saved
                      : null,
                ),
                AppButton(
                  _saving ? 'Saving…' : 'Save',
                  primary: true,
                  onPressed: _dirty && !_saving ? _save : null,
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Essentials view's section of the open workspace, each but Created files the same node as
/// in the tree, or the text of one of its documents. On a [phone] its answer settings are the
/// few a phone shows.
Widget essentialSection(
  BuildContext context,
  FileNode? node, {
  bool phone = false,
}) {
  final scope = AppScope.of(context);
  final files = scope.files;
  final workspace = scope.chat.active;
  if (workspace == null) return const Blank('No workspace is open.');
  if (files.reading != null) return const TextViewer();
  final section = files.section;
  final key = ValueKey('${node?.path}#${files.revision}');
  return switch (section) {
    // Keyed by workspace, so what waits to be added stays with it.
    FilesSection.documents => EssentialDocs(key: ValueKey(workspace.slug)),
    FilesSection.created => CreatedFiles(workspace: workspace.name),
    _ when files.contentLoading || (node == null && files.loading) =>
      const Blank('Loading…'),
    _ when node == null => Blank(
      'The server did not send this workspace\'s '
      '${section == FilesSection.instructions ? 'prompt' : 'settings'}.',
    ),
    FilesSection.instructions => _Editor(key: key, node: node),
    FilesSection.answers => _SettingsPage(
      key: key,
      node: node,
      plain: true,
      phone: phone,
    ),
  };
}
