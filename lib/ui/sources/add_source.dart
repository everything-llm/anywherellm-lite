import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../widgets/buttons.dart';
import '../widgets/doc_details.dart';
import '../widgets/fields.dart';

enum _Adding { none, link, text }

/// Adds a source that is not a file: a web page the server reads in, or text pasted here, each
/// with optional details. Its form takes the place of its row of ways to add one.
class AddSource extends StatefulWidget {
  const AddSource({super.key, required this.leading});

  /// What the row holds before Add a link, such as an Add a file button. It gives way to an
  /// open form.
  final Widget leading;

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

  /// Adds the link. One that is not a link keeps the form, and Sources says why.
  void _addLink() {
    if (AppScope.of(context).sources.addLink(_link.text, meta: _details.meta)) {
      _close();
    }
  }

  void _addText() {
    final title = _title.text;
    final text = _text.text;
    final meta = _details.meta;
    if (title.trim().isEmpty || text.trim().isEmpty) return;
    _close();
    AppScope.of(context).sources.addText(title, text, meta: meta);
  }

  Widget _row() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      widget.leading,
      AppButton(
        'Add a link',
        leading: 'link',
        onPressed: () => _open(_Adding.link),
      ),
      AppButton(
        'Paste text',
        leading: 'pencil',
        onPressed: () => _open(_Adding.text),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => switch (_adding) {
    _Adding.none => _row(),
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
          keyboardType: TextInputType.url,
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
        AppField(
          controller: _text,
          label: 'Text to add',
          hint: 'Paste the text here',
          maxLines: 5,
        ),
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
        builder: (context, _) => ActionRow([
          AppButton('Cancel', onPressed: onCancel),
          AppButton('Add', primary: true, onPressed: canAdd() ? onAdd : null),
        ]),
      ),
    ],
  );
}
