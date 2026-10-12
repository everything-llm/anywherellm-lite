import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/server_models.dart';
import '../app_scope.dart';
import '../links.dart';
import '../settings/rows.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/sheet.dart';
import '../widgets/side_panel.dart';
import '../widgets/tappable.dart';
import 'passages_sheet.dart';

/// All of an answer's sources in a sheet: how many, then each in the order the answer cites it,
/// with its site or how many passages were read.
class CitedPanel extends StatelessWidget {
  const CitedPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    final cited = shell.cited ?? const <Citation>[];
    return SidePanel(
      title: 'Sources',
      onClose: shell.closeCited,
      sheetHeight: SheetHeight.fit,
      child: CitedSources(cited),
    );
  }
}

/// How many [citations] there are, under the sheet's title, then each a row that opens what it
/// names: a web page in the browser, a file's passages, or the file in Documents.
class CitedSources extends StatelessWidget {
  const CitedSources(this.citations, {super.key});

  final List<Citation> citations;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final web = citations.every((c) => c.url != null);
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Text(
            web
                ? '${plural(citations.length, 'web page', 'web pages')} the agent read.'
                : plural(citations.length, 'source', 'sources'),
            style: Type.sans(13, color: t.muted, height: 1.45),
          ),
        ),
        FieldCard(inSheet: true, [
          for (final (i, c) in citations.indexed) _CitedRow(c, number: i + 1),
        ]),
      ],
    );
  }
}

class _CitedRow extends StatelessWidget {
  const _CitedRow(this.citation, {required this.number});

  final Citation citation;
  final int number;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final url = citation.url;
    final present = scope.sources.byTitle(citation.title) != null;
    final passages = citation.passages.length;
    final about = url != null
        ? url.host
        : passages > 0
        ? plural(passages, 'passage', 'passages')
        : present
        ? 'In Documents'
        : null;
    final VoidCallback? open = url != null
        ? () => openLink(context, url.toString())
        : passages > 0 && present
        ? () => scope.shell.togglePassages(citation)
        : present
        ? () {
            scope.shell.openSources();
            scope.sources.flash(citation.title);
          }
        : null;
    return Tappable(
      label: [citation.title, ?about].join(', '),
      onTap: open,
      child: Container(
        constraints: const BoxConstraints(minHeight: 80),
        padding: const EdgeInsets.symmetric(
          horizontal: FieldCard.inset,
          vertical: 8,
        ),
        child: Row(
          spacing: 14,
          children: [
            CitationNumber(number, live: open != null),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    citation.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sans(15, color: t.ink),
                  ),
                  if (about != null)
                    Text(
                      about,
                      style: Type.sans(13, color: t.muted, height: 1.45),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
