import 'package:flutter/material.dart';

import '../../core/server_models.dart';
import 'buttons.dart';
import 'fields.dart';

/// The text of a document's details while they are being typed.
class DocDetailsController {
  final title = TextEditingController();
  final author = TextEditingController();
  final description = TextEditingController();
  final source = TextEditingController();

  DocMeta get meta => DocMeta(
    title: title.text,
    author: author.text,
    description: description.text,
    source: source.text,
  );

  void clear() {
    for (final c in [title, author, description, source]) {
      c.clear();
    }
  }

  void dispose() {
    for (final c in [title, author, description, source]) {
      c.dispose();
    }
  }
}

/// A Details button that shows a document's title, author, source and description fields. All
/// are optional; the server fills what is left empty. [title] false leaves out the title, for a
/// form that has its own, and [titleHint] is what the title becomes when left empty.
class DocDetails extends StatefulWidget {
  const DocDetails(
    this.controller, {
    super.key,
    this.title = true,
    this.titleHint,
    this.of,
  });

  final DocDetailsController controller;
  final bool title;
  final String? titleHint;

  /// The name of what the details are about, for a screen reader, as in a list of files.
  final String? of;

  @override
  State<DocDetails> createState() => _DocDetailsState();
}

class _DocDetailsState extends State<DocDetails> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final of = widget.of == null ? '' : ' of ${widget.of}';
    final toggle = Align(
      alignment: Alignment.centerLeft,
      child: TextAction(
        _open ? 'close' : 'pencil',
        _open ? 'Hide details' : 'Details',
        () => setState(() => _open = !_open),
        semanticLabel: _open ? 'Hide details$of' : 'Details$of',
      ),
    );
    if (!_open) return toggle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        toggle,
        const SizedBox(height: 6),
        for (final (field, label, hint) in [
          if (widget.title) (c.title, 'Title$of', widget.titleHint ?? 'Title'),
          (c.author, 'Author$of', 'Author'),
          (c.source, 'Source$of', 'Source, such as where it came from'),
          (c.description, 'Description$of', 'Description'),
        ]) ...[
          AppField(controller: field, label: label, hint: hint),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
