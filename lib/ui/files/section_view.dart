import 'package:flutter/material.dart';

import '../../core/files.dart';
import '../app_scope.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import 'text_viewer.dart';
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
  const _Editor({super.key, required this.prompt});

  /// The workspace's prompt as last read.
  final String prompt;

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
    _saved = widget.prompt;
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
      padding: Sizes.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Semantics(
              label: 'PROMPT.md',
              textField: true,
              child: TextField(
                controller: _draft,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                autocorrect: false,
                enableSuggestions: false,
                style: Type.textArea(15.5, t.ink),
                cursorColor: t.accent,
                decoration: editorDecoration(context, t.panel).copyWith(
                  // An empty prompt says what applies instead.
                  hintText:
                      'Empty: the server\'s default system prompt applies.',
                  hintStyle: Type.textArea(15.5, t.muted),
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

/// A page of the open workspace: its instructions or its answer settings, the section
/// [FilesController.section] picks, or the text of one of its documents.
Widget workspaceSection(BuildContext context) {
  final scope = AppScope.of(context);
  final files = scope.files;
  final workspace = scope.chat.active;
  if (workspace == null) return const Blank('No workspace is open.');
  if (files.reading != null) return const TextViewer();
  final section = files.section;
  final detail = files.detail(workspace.slug);
  final key = ValueKey('${workspace.slug}#$section#${files.revision}');
  return switch (section) {
    _ when detail == null && files.loading => const Blank('Loading…'),
    _ when detail == null => Blank(
      'The server did not send this workspace\'s '
      '${section == FilesSection.instructions ? 'prompt' : 'settings'}.',
    ),
    FilesSection.instructions => _Editor(key: key, prompt: detail.prompt ?? ''),
    FilesSection.answers when detail.settings == null => const Blank(
      'The server did not send this workspace\'s settings.',
    ),
    FilesSection.answers => SettingsForm(key: key, slug: workspace.slug),
  };
}
