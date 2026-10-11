import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/server_models.dart';
import '../app_scope.dart';
import '../layout.dart';
import '../links.dart';
import '../settings/rows.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/side_panel.dart';
import '../widgets/tappable.dart';
import 'passages_sheet.dart';

/// All of an answer's sources in the panel to the right, or on a phone in a sheet: how many,
/// then each in the order the answer cites it, with its site or how many passages were read.
class CitedPanel extends StatelessWidget {
  const CitedPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    final cited = shell.cited ?? const <Citation>[];
    final phone = ScreenClass.ofContext(context).isPhone;
    return SidePanel(
      title: phone ? 'Sources' : 'Sources for this answer',
      about: plural(cited.length, 'source', 'sources'),
      onClose: shell.closeCited,
      child: CitedSources(cited),
    );
  }
}

/// [citations], each a row that opens what it names: a web page in the browser, a file's
/// passages, or the file in Documents.
class CitedSources extends StatelessWidget {
  const CitedSources(this.citations, {super.key});

  final List<Citation> citations;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final phone = ScreenClass.ofContext(context).isPhone;
    final rows = [
      for (final (i, c) in citations.indexed) _CitedRow(c, number: i + 1),
    ];
    final web = citations.isNotEmpty && citations.every((c) => c.url != null);
    return ListView(
      padding: phone ? EdgeInsets.zero : const EdgeInsets.only(top: 4),
      children: [
        if (phone)
          FieldCard(inSheet: true, rows)
        else
          for (final row in rows)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.line2)),
              ),
              child: row,
            ),
        if (web && !phone)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'A source opens its page in the browser.',
              style: Type.sans(12.5, color: t.muted, height: 1.45),
            ),
          ),
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
    final phone = ScreenClass.ofContext(context).isPhone;
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
        ? () => scope.shell.togglePassages(number, citation)
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
        constraints: BoxConstraints(minHeight: phone ? 64 : 56),
        padding: phone
            ? const EdgeInsets.symmetric(
                horizontal: FieldCard.inset,
                vertical: 8,
              )
            : const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: phone ? 14 : 10,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: CitationNumber(number, live: open != null),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    citation.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sans(phone ? 15 : 14, color: t.ink),
                  ),
                  if (about != null)
                    Text(about, style: Type.sans(13, color: t.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
