import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/server_models.dart';
import '../../core/sources.dart';
import '../app_scope.dart';
import '../state/shell_controller.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/sheet.dart';
import '../widgets/buttons.dart';

/// What an answer read from one file, in a sheet opened from an answer's list of sources. Close,
/// Esc and Back put back what the sheet showed.
class PassagesPanel extends StatelessWidget {
  const PassagesPanel({super.key});

  // Const where the shell builds it, so it listens to the shell for the citation it shows.
  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    return ListenableBuilder(
      listenable: shell,
      builder: (context, _) {
        final citation = shell.passages;
        if (citation == null) return const SizedBox.shrink();
        return SheetFrame(
          title: 'Passages read from this file',
          onClose: shell.closePassages,
          height: SheetHeight.tall,
          child: PassagesView(citation: citation, onClose: shell.closePassages),
        );
      },
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
            child: Text('${citation.title} · $count', style: Type.note(t.ink)),
          ),
          const SizedBox(height: 12),
          for (final passage in passages) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: t.ground,
                border: Border.all(color: t.tileEdge),
                borderRadius: BorderRadius.circular(Sizes.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 4,
                children: [
                  if (passage.score case final score?)
                    Text(
                      matchText(score),
                      textAlign: TextAlign.end,
                      style: Type.note(t.ink),
                    ),
                  SelectableText(passage.text, style: Type.body(t.ink)),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (file != null) ...[
            const SizedBox(height: 8),
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

/// A citation's [number] in a small circle [diameter] across, in the accent while it leads
/// somewhere ([live]).
class CitationNumber extends StatelessWidget {
  const CitationNumber(
    this.number, {
    super.key,
    this.live = true,
    this.diameter = 17,
  });

  final int number;
  final bool live;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: live ? t.accent : t.muted,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: Type.sans(
          13,
          weight: FontWeight.w600,
          color: t.onAccent,
          height: 1,
        ),
      ),
    );
  }
}

/// Shows the cited file [title] in Documents, lit up: the sheet, or the pane on a wide window.
void showCitedInDocuments(BuildContext context, String title) {
  final scope = AppScope.of(context);
  scope.shell.openSources(asPane: Wide.split(context));
  scope.sources.flash(title);
}
