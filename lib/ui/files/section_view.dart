import 'package:flutter/material.dart';

import '../../core/files.dart';
import '../app_scope.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/scroll_fades.dart';
import '../widgets/window_insets.dart';
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
        style: Type.body(Tokens.of(context).muted),
      ),
    ),
  );
}

/// A page's header, with [action] at its end when there is one, and the notices under it.
typedef PageTop = Widget Function(Widget? action);

/// The editor for a workspace's `PROMPT.md`, under [top], the page's header: full width on the
/// tile, in the mono face its Markdown and tags read best in, with a scrollbar once the text runs
/// past it. It takes all the height there is. Revert and Save show at the header's end only while
/// the text differs from what was read, or is being saved. Its key changes each time the text is
/// read afresh, which drops the draft.
class _Editor extends StatefulWidget {
  const _Editor({super.key, required this.prompt, required this.top});

  /// The workspace's prompt as last read.
  final String prompt;
  final PageTop top;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final TextEditingController _draft;
  late final String _saved;
  final _scroll = ScrollController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _saved = widget.prompt;
    _draft = TextEditingController(text: _saved);
  }

  @override
  void dispose() {
    _scroll.dispose();
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

  /// Revert and Save, sharing what the header leaves of its line, or null while there is
  /// nothing to save.
  Widget? _buttons() {
    if (!_dirty && !_saving) return null;
    final ready = _dirty && !_saving;
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Flexible(
            child: AppButton(
              'Revert',
              quiet: true,
              onPressed: ready ? () => _draft.text = _saved : null,
            ),
          ),
          Flexible(
            child: AppButton(
              _saving ? 'Saving…' : 'Save',
              primary: true,
              compact: true,
              onPressed: ready ? _save : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    OutlineInputBorder ring(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: color, width: width),
    );
    final text = Type.code(t.ink);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Only the header follows the draft, so typing rebuilds nothing else.
        ListenableBuilder(
          listenable: _draft,
          builder: (context, _) => widget.top(_buttons()),
        ),
        Expanded(
          child: FieldName(
            label: 'PROMPT.md',
            child: Scrollbar(
              controller: _scroll,
              child: TextField(
                controller: _draft,
                scrollController: _scroll,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                autocorrect: false,
                enableSuggestions: false,
                style: text,
                cursorColor: t.accent,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: t.tile,
                  // It runs on behind the navigation bar, its text clear of it.
                  contentPadding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    24 + WindowInsets.of(context).bottom,
                  ),
                  enabledBorder: InputBorder.none,
                  focusedBorder: ring(t.accent, 2),
                  // An empty prompt says what applies instead.
                  hintText:
                      'Empty: the server\'s default system prompt applies.',
                  hintStyle: text.copyWith(color: t.muted),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A page of the open workspace under [top], its header: its instructions or its answer
/// settings, the section [FilesController.section] picks. The instructions put their buttons in
/// the header; any other page scrolls under it.
Widget workspaceSection(BuildContext context, {required PageTop top}) {
  final scope = AppScope.of(context);
  final files = scope.files;
  final workspace = scope.chat.active;
  Widget under(Widget page) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      top(null),
      Expanded(child: ScrollFades(child: page)),
    ],
  );
  if (workspace == null) return under(const Blank('No workspace is open.'));
  final section = files.section;
  final detail = files.detail(workspace.slug);
  final key = ValueKey('${workspace.slug}#$section#${files.revision}');
  return switch (section) {
    _ when detail == null && files.loading => under(const Blank('Loading…')),
    _ when detail == null => under(
      Blank(
        'The server did not send this workspace\'s '
        '${section == FilesSection.instructions ? 'prompt' : 'settings'}.',
      ),
    ),
    FilesSection.instructions => _Editor(
      key: key,
      prompt: detail.prompt ?? '',
      top: top,
    ),
    FilesSection.answers when detail.settings == null => under(
      const Blank('The server did not send this workspace\'s settings.'),
    ),
    FilesSection.answers => under(SettingsForm(key: key, slug: workspace.slug)),
  };
}
