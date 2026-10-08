import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/files.dart';
import '../../core/server_models.dart';
import '../app_scope.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';

/// What an answer read from one file, in the sheet a citation opens on a phone: the citation's
/// [number] and the file, how many passages, then each passage, closest first, with how close
/// it was to the question when the server said, and View extracted text, which shows the
/// file's whole text in the workspace's pages.
class PassagesView extends StatelessWidget {
  const PassagesView({
    super.key,
    required this.number,
    required this.citation,
    required this.onClose,
  });

  final int number;
  final Citation citation;

  /// Closes the sheet, as View extracted text does before it shows the text.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final passages = citation.passages;
    final file = scope.sources.byTitle(citation.title);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 17,
                height: 17,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: Type.sans(
                    10.5,
                    weight: FontWeight.w600,
                    color: t.onaccent,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      citation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.sans(
                        14,
                        weight: FontWeight.w500,
                        color: t.ink,
                      ),
                    ),
                    Text(
                      passages.length == 1
                          ? '1 passage'
                          : '${passages.length} passages, closest first',
                      style: Type.sans(12, color: t.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final passage in passages) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: t.panel,
                border: Border.all(color: t.line2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (passage.score case final score?) ...[
                    Text(
                      '${(score * 100).round()}% match',
                      style: Type.sans(12.5, color: t.muted),
                    ),
                    const SizedBox(height: 4),
                  ],
                  SelectableText(
                    passage.text,
                    style: Type.sans(14, color: t.ink2, height: 1.55),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (file != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                'View extracted text',
                onPressed: () {
                  onClose();
                  final files = scope.files;
                  files.showEssentials(true);
                  unawaited(
                    files
                        .openSection(FilesSection.documents)
                        .then((_) => files.viewText(file.path, file.title)),
                  );
                  scope.shell.showPane(Pane.files);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
