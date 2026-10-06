import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/inline_input.dart';
import '../widgets/tappable.dart';

enum _Adding { none, link, text }

/// Adds a source that is not a file: a web page the server reads in, or text pasted here.
class AddSource extends StatefulWidget {
  const AddSource({super.key});

  @override
  State<AddSource> createState() => _AddSourceState();
}

class _AddSourceState extends State<AddSource> {
  _Adding _adding = _Adding.none;
  final _link = TextEditingController();
  final _title = TextEditingController();
  final _text = TextEditingController();

  @override
  void dispose() {
    _link.dispose();
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  void _open(_Adding adding) => setState(() => _adding = adding);

  void _close() {
    _link.clear();
    _title.clear();
    _text.clear();
    setState(() => _adding = _Adding.none);
  }

  void _addLink() {
    final url = _link.text;
    _close();
    if (url.trim().isNotEmpty) AppScope.of(context).sources.addLink(url);
  }

  void _addText() {
    final title = _title.text;
    final text = _text.text;
    if (title.trim().isEmpty || text.trim().isEmpty) return;
    _close();
    AppScope.of(context).sources.addText(title, text);
  }

  @override
  Widget build(BuildContext context) => switch (_adding) {
    _Adding.none => Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        _TextAction('link', 'Add a link', () => _open(_Adding.link)),
        _TextAction('doc', 'Paste text', () => _open(_Adding.text)),
      ],
    ),
    _Adding.link => InlineInput(
      controller: _link,
      label: 'Web page to add',
      hint: 'https://…',
      height: 36,
      onSubmit: _addLink,
      onCancel: _close,
    ),
    _Adding.text => _TextForm(
      title: _title,
      text: _text,
      onAdd: _addText,
      onCancel: _close,
    ),
  };
}

/// A small text button with an icon before it.
class _TextAction extends StatelessWidget {
  const _TextAction(this.icon, this.label, this.onTap);

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: label,
      onTap: onTap,
      radius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: IconSize.xs, color: t.accent),
            const SizedBox(width: 6),
            Text(label, style: Type.sans(13, color: t.accent)),
          ],
        ),
      ),
    );
  }
}

/// A title and the text to save under it.
class _TextForm extends StatelessWidget {
  const _TextForm({
    required this.title,
    required this.text,
    required this.onAdd,
    required this.onCancel,
  });

  final TextEditingController title;
  final TextEditingController text;
  final VoidCallback onAdd;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppField(controller: title, label: 'Title', hint: 'Title'),
        const SizedBox(height: 8),
        Semantics(
          label: 'Text to add',
          textField: true,
          child: TextField(
            controller: text,
            minLines: 3,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            style: Type.sans(14, color: t.ink, height: 1.45),
            cursorColor: t.accent,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: t.bg,
              hintText: 'Paste the text here',
              hintStyle: Type.sans(14, color: t.fade),
              contentPadding: const EdgeInsets.all(12),
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
        const SizedBox(height: 8),
        ListenableBuilder(
          listenable: Listenable.merge([title, text]),
          builder: (context, _) => Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton('Cancel', onPressed: onCancel),
              AppButton(
                'Add',
                primary: true,
                onPressed: title.text.trim().isEmpty || text.text.trim().isEmpty
                    ? null
                    : onAdd,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
