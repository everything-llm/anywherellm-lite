import 'package:flutter/material.dart';

import '../../core/files.dart';
import '../app_scope.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import 'essentials.dart';
import 'settings_form.dart';

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

/// The editor for a workspace's `PROMPT.md`, as prose, with Revert and Save sharing the line.
/// Its key changes each time the text is read afresh, which drops the draft.
class _Editor extends StatefulWidget {
  const _Editor({super.key, required this.node});

  final FileNode node;

  @override
  State<_Editor> createState() => _EditorState();
}

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                style: Type.sans(15.5, color: t.ink, height: 1.5),
                cursorColor: t.accent,
                decoration: editorDecoration(context, t.panel).copyWith(
                  // An empty prompt says what applies instead.
                  hintText:
                      'Empty: the server\'s default system prompt applies.',
                  hintStyle: Type.sans(15.5, color: t.muted, height: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Only the buttons follow the draft, so typing rebuilds nothing else. They show once
          // the text has changed, in a line kept for them, as the design canvas draws it.
          ListenableBuilder(
            listenable: _draft,
            builder: (context, _) => ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: !_dirty && !_saving
                  ? null
                  : ActionRow(even: true, [
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
          ),
        ],
      ),
    );
  }
}

/// A page of the open workspace: its instructions or its answer settings, the node
/// [FilesController.section] picks, or the text of one of its documents.
Widget essentialSection(BuildContext context, FileNode? node) {
  final scope = AppScope.of(context);
  final files = scope.files;
  final workspace = scope.chat.active;
  if (workspace == null) return const Blank('No workspace is open.');
  if (files.reading != null) return const TextViewer();
  final section = files.section;
  final key = ValueKey('${node?.path}#${files.revision}');
  return switch (section) {
    // The documents are a sheet over the pages; this shows only until the text picked reads.
    FilesSection.documents => const Blank('Loading…'),
    _ when files.contentLoading || (node == null && files.loading) =>
      const Blank('Loading…'),
    _ when node == null => Blank(
      'The server did not send this workspace\'s '
      '${section == FilesSection.instructions ? 'prompt' : 'settings'}.',
    ),
    FilesSection.instructions => _Editor(key: key, node: node),
    FilesSection.answers => SettingsForm(key: key, slug: node.slug!),
  };
}
