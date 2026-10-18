import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../settings/rows.dart';
import 'workspace_pages.dart';

/// The page of the text the server read from the document View extracted text opened, under
/// the header that names it and offers Download: its kind and size, whether answers use it, the
/// text in a card, and Remove from workspace.
class TextViewer extends StatelessWidget {
  const TextViewer({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final files = scope.files;
    final t = Tokens.of(context);
    final path = files.reading?.path;
    final file = scope.sources.files.where((f) => f.path == path).firstOrNull;
    final text = files.text;
    return ListView(
      padding: Sizes.pageIn(context),
      children: [
        if (file != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FieldCard.inset,
              0,
              FieldCard.inset,
              16,
            ),
            child: Row(
              spacing: 12,
              children: [
                Expanded(
                  child: Text(
                    '${file.tile} · ${file.size}',
                    style: Type.sans(13, color: t.muted),
                  ),
                ),
                Text(
                  file.on ? 'Used in answers' : 'Not used',
                  style: Type.sans(13, color: t.muted),
                ),
              ],
            ),
          ),
        if (files.contentLoading)
          Text('Loading…', style: Type.sans(14, color: t.muted))
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            decoration: cardDecoration(t),
            child: SelectableText(
              text ?? 'The server sent no text for this document.',
              style: Type.sans(
                15.5,
                color: text == null ? t.muted : t.ink2,
                height: 1.65,
              ),
            ),
          ),
        const SizedBox(height: 16),
        const CardCaption('The text the server read from this document.'),
        if (file != null) ...[
          const SizedBox(height: 20),
          ActionRow(even: true, [
            AppButton(
              'Remove from workspace',
              danger: true,
              onPressed: () {
                closeDocText(scope);
                scope.sources.remove(file);
              },
            ),
          ]),
        ],
      ],
    );
  }
}
