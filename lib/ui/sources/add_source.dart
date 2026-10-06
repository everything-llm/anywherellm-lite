import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/doc_details.dart';
import '../widgets/fields.dart';

enum _Adding { none, link, text }

/// Adds a source that is not a file: a web page the server reads in, or text pasted here, each
/// with optional details.
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
  final _details = DocDetailsController();

  @override
  void dispose() {
    _link.dispose();
    _title.dispose();
    _text.dispose();
    _details.dispose();
    super.dispose();
  }

  void _open(_Adding adding) => setState(() => _adding = adding);

  void _close() {
    _link.clear();
    _title.clear();
    _text.clear();
    _details.clear();
    setState(() => _adding = _Adding.none);
  }

  void _addLink() {
    final url = _link.text;
    final meta = _details.meta;
    if (url.trim().isEmpty) return;
    _close();
    AppScope.of(context).sources.addLink(url, meta: meta);
  }

  void _addText() {
    final title = _title.text;
    final text = _text.text;
    final meta = _details.meta;
    if (title.trim().isEmpty || text.trim().isEmpty) return;
    _close();
    AppScope.of(context).sources.addText(title, text, meta: meta);
  }

  @override
  Widget build(BuildContext context) => switch (_adding) {
    _Adding.none => Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        TextAction('link', 'Add a link', () => _open(_Adding.link)),
        TextAction('doc', 'Paste text', () => _open(_Adding.text)),
      ],
    ),
    _Adding.link => _Form(
      ready: _link,
      canAdd: () => _link.text.trim().isNotEmpty,
      onAdd: _addLink,
      onCancel: _close,
      children: [
        AppField(
          controller: _link,
          label: 'Web page to add',
          hint: 'https://…',
          onSubmitted: (_) => _addLink(),
        ),
        DocDetails(_details),
      ],
    ),
    _Adding.text => _Form(
      ready: Listenable.merge([_title, _text]),
      canAdd: () =>
          _title.text.trim().isNotEmpty && _text.text.trim().isNotEmpty,
      onAdd: _addText,
      onCancel: _close,
      children: [
        AppField(controller: _title, label: 'Title', hint: 'Title'),
        _TextBox(_text),
        DocDetails(_details, title: false),
      ],
    ),
  };
}

/// [children] spaced in a column, then Cancel and Add. Add is off until [canAdd], checked
/// whenever [ready] changes.
class _Form extends StatelessWidget {
  const _Form({
    required this.ready,
    required this.canAdd,
    required this.onAdd,
    required this.onCancel,
    required this.children,
  });

  final Listenable ready;
  final bool Function() canAdd;
  final VoidCallback onAdd;
  final VoidCallback onCancel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final child in children) ...[child, const SizedBox(height: 8)],
      ListenableBuilder(
        listenable: ready,
        builder: (context, _) => Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            AppButton('Cancel', onPressed: onCancel),
            AppButton('Add', primary: true, onPressed: canAdd() ? onAdd : null),
          ],
        ),
      ),
    ],
  );
}

/// The several lines of text to save.
class _TextBox extends StatelessWidget {
  const _TextBox(this.controller);

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      label: 'Text to add',
      textField: true,
      child: TextField(
        controller: controller,
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
    );
  }
}
