import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/server_models.dart';
import '../app_scope.dart';
import '../links.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/sheet.dart';
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
    return SheetFrame(
      title: 'Sources',
      onClose: shell.closeCited,

      child: CitedSources(cited),
    );
  }
}

/// How many [citations] there are, under the sheet's title, then each a tile that opens what it
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
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Text(
            web
                ? '${plural(citations.length, 'web page', 'web pages')} the agent read.'
                : plural(citations.length, 'source', 'sources'),
            style: Type.note(t.ink),
          ),
        ),
        for (final (i, c) in citations.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          _CitedRow(c, number: i + 1),
        ],
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
        ? () => openLink(context, url)
        : passages > 0 && present
        ? () => scope.shell.togglePassages(citation)
        : present
        ? () => showCitedInDocuments(context, citation.title)
        : null;
    return Tappable(
      label: [citation.title, ?about].join(', '),
      onTap: open,
      radius: BorderRadius.circular(Sizes.control),
      color: t.ground,
      side: BorderSide(color: t.tileEdge),
      child: Container(
        constraints: const BoxConstraints(minHeight: Sizes.cardRow),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          spacing: 12,
          children: [
            CitationNumber(number, live: open != null, diameter: 22),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    citation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.body(t.ink, weight: FontWeight.w600),
                  ),
                  if (about != null)
                    Text(
                      about,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.note(t.ink),
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
