import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/server_models.dart';
import '../app_scope.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/sheet.dart';
import '../widgets/buttons.dart';

/// What an answer read from one file, in a sheet opened from an answer's list of sources. Close,
/// Esc and Back put back what the sheet showed.
class PassagesPanel extends StatelessWidget {
  const PassagesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    final citation = shell.passages!;
    return SheetFrame(
      title: 'Passages read from this file',
      onClose: shell.closePassages,
      height: SheetHeight.tall,
      child: PassagesView(citation: citation, onClose: shell.closePassages),
    );
  }
}

/// What an answer read from one file, in the sheet a citation opens: the file with how many
/// passages, then each passage, closest first, with how close it was to the question at its top
/// right when the server said, and View extracted text, which shows the file's whole text in the
/// workspace's pages.
class PassagesView extends StatelessWidget {
  const PassagesView({
    super.key,
    required this.citation,
    required this.onClose,
  });

  final Citation citation;

  /// Closes the sheet, as View extracted text does before it shows the text.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final passages = citation.passages;
    final file = scope.sources.byTitle(citation.title);
    final count = passages.length == 1
        ? '1 passage'
        : '${passages.length} passages, closest first';
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The file and its count in one line.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${citation.title} · $count',
              style: Type.sans(13, color: t.muted, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          for (final passage in passages) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: t.bg,
                border: Border.all(color: t.line2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (passage.score case final score?)
                    Text(
                      '${(score * 100).round()}% match',
                      textAlign: TextAlign.end,
                      style: Type.sans(13.5, color: t.muted, height: 1.5),
                    ),
                  SelectableText(
                    passage.text,
                    style: Type.sans(14, color: t.ink2, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (file != null) ...[
            const SizedBox(height: 4),
            ActionRow(even: true, alignment: WrapAlignment.start, [
              AppButton(
                'View extracted text',
                onPressed: () {
                  onClose();
                  final files = scope.files;
                  unawaited(files.viewText(file.path, file.title));
                  scope.shell.showPane(Pane.files);
                },
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

/// A citation's [number] in a small circle, in the accent while it leads somewhere ([live]).
class CitationNumber extends StatelessWidget {
  const CitationNumber(this.number, {super.key, this.live = true});

  final int number;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      width: 17,
      height: 17,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: live ? t.accent : t.muted,
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
    );
  }
}
