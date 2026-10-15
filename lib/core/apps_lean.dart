import 'package:markdown/markdown.dart' as md;

import 'browser.dart';
import 'chat.dart';

/// Whether [link] is an apps-lean app's page: `/apps-lean/<token>.html`, which the skill
/// publishes into AnythingLLM's web folder.
bool isAppsLeanPage(Uri link, Uri? server) =>
    isSkillPage(link, server, 'apps-lean');

/// An app's card in an answer: the quote an apps-lean answer ends with, `> [**Groceries**](<page>)`
/// over the lines that say what changed. It is drawn as one tappable card.
class AppCard {
  const AppCard({
    required this.title,
    required this.href,
    this.lines = const [],
  });

  /// The linked title, as text.
  final String title;

  /// The link's address as the answer wrote it.
  final String href;

  /// What the answer says about the change, a line each, as plain text.
  final List<String> lines;

  /// [lines] as one text.
  String get about => lines.join('\n');
}

/// The [AppCard] a Markdown quote makes, or null when it is not one: its first line must open
/// with a link, alone or inside bold or italics, to an apps-lean page on [server]. Any other
/// quote, and a link in a paragraph that is not in one, stays as written.
AppCard? appCardOf(md.Element quote, Uri? server) {
  if (quote.tag != 'blockquote') return null;
  final blocks = quote.children ?? const <md.Node>[];
  if (blocks.firstOrNull case md.Element(tag: 'p', :final children?)) {
    return _cardOf(children, blocks.skip(1), server);
  }
  return null;
}

/// The card of a quote whose first paragraph holds [inline] and which goes on with [more].
AppCard? _cardOf(List<md.Node> inline, Iterable<md.Node> more, Uri? server) {
  final at = inline.indexWhere((n) => !(n is md.Text && n.text.trim().isEmpty));
  if (at < 0) return null;
  final link = _linkIn(inline[at]);
  final href = link?.attributes['href'];
  if (link == null || href == null) return null;
  final url = openableLink(href, server: server);
  if (url == null || !isAppsLeanPage(url, server)) return null;
  final title = link.textContent.trim();
  if (title.isEmpty) return null;
  final rest = [
    inline.skip(at + 1).map((n) => n.textContent).join(),
    for (final block in more) ..._textsOf(block),
  ];
  return AppCard(
    title: title,
    href: href,
    lines: [
      for (final text in rest)
        for (final line in text.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
    ],
  );
}

/// The link [node] is, or that it wraps alone in bold or italics.
md.Element? _linkIn(md.Node node) {
  if (node is! md.Element) return null;
  if (node.tag == 'a') return node;
  if (node.tag == 'strong' || node.tag == 'em') {
    final only = node.children;
    if (only != null && only.length == 1) return _linkIn(only.first);
  }
  return null;
}

/// The text of [block], one entry for each item when it is a list.
Iterable<String> _textsOf(md.Node block) =>
    block is md.Element && (block.tag == 'ul' || block.tag == 'ol')
    ? [for (final item in block.children ?? const <md.Node>[]) item.textContent]
    : [block.textContent];
