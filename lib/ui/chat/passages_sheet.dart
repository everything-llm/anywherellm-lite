import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/files.dart';
import '../../core/server_models.dart';
import '../app_scope.dart';
import '../layout.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/side_panel.dart';

/// What an answer read from one file, beside the chat on a desktop, as the design canvas draws
/// it. Close, Esc and Back put back what the panel showed.
class PassagesPanel extends StatelessWidget {
  const PassagesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    final (:number, :citation) = shell.passages!;
    return SidePanel(
      title: 'Passages read from this file',
      onClose: shell.closePassages,
      child: PassagesView(
        number: number,
        citation: citation,
        onClose: shell.closePassages,
      ),
    );
  }
}

/// What an answer read from one file, in the sheet a citation opens on a phone or the panel
/// beside the chat on a desktop: the citation's [number] and the file with how many passages,
/// at the line's end on a phone, then each passage, closest first, with how close it was to the question
/// at its top right when the server said, and View extracted text, which shows the file's
/// whole text in the workspace's pages.
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
    final phone = ScreenClass.ofContext(context).isPhone;
    final name = Text(
      citation.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Type.sans(14, weight: FontWeight.w500, color: t.ink),
    );
    final count = Text(
      passages.length == 1
          ? '1 passage'
          : '${passages.length} passages, closest first',
      style: Type.sans(12, color: t.muted),
    );
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A phone's sheet says the file and its count in one line; the panel beside a
          // desktop's chat numbers the file and puts the count under its name.
          if (phone)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${citation.title} · ${count.data}',
                style: Type.sans(13, color: t.muted, height: 1.4),
              ),
            )
          else
            Row(
              children: [
                CitationNumber(number),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [name, count],
                  ),
                ),
              ],
            ),
          SizedBox(height: phone ? 16 : 10),
          for (final passage in passages) ...[
            Container(
              padding: phone
                  ? const EdgeInsets.symmetric(horizontal: 18, vertical: 16)
                  : const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: phone ? t.bg : t.panel,
                border: Border.all(color: t.line2),
                borderRadius: BorderRadius.circular(phone ? 20 : 12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (passage.score case final score?) ...[
                    Text(
                      '${(score * 100).round()}% match',
                      textAlign: TextAlign.end,
                      style: Type.sans(12.5, color: t.muted, height: 1.4),
                    ),
                    const SizedBox(height: 4),
                  ],
                  SelectableText(
                    passage.text,
                    style: Type.sans(14, color: t.ink2, height: 1.5),
                  ),
                ],
              ),
            ),
            SizedBox(height: phone ? 16 : 8),
          ],
          if (file != null) ...[
            const SizedBox(height: 4),
            ActionRow(even: phone, alignment: WrapAlignment.start, [
              AppButton(
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
    // A little larger on a phone, as the design canvas draws it.
    final phone = ScreenClass.ofContext(context).isPhone;
    return Container(
      width: phone ? 17 : 16,
      height: phone ? 17 : 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: live ? t.accent : t.muted,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$number',
        style: Type.sans(
          phone ? 10.5 : 10,
          weight: FontWeight.w600,
          color: t.onaccent,
          height: 1,
        ),
      ),
    );
  }
}
