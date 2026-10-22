import 'package:markdown/markdown.dart' as md;

import 'chat.dart';
import 'skill_pages.dart';

/// The element [AppLinkSyntax] wraps a paragraph in.
const appCardTag = 'appcard';

/// A paragraph that opens with a link to an apps-lean page, `[**Groceries**](/apps-lean/q9Z.html)
/// - Added Tea`, as an [appCardTag] around the paragraph, so it can be drawn as an app's card like
/// the quote an answer ends with. Whether the link is the connected server's own is for the
/// builder to say: any other is drawn as the paragraph it is. It reads top-level paragraphs
/// only: the opening paragraph of a quote is read by [appCardOf] as it stands.
class AppLinkSyntax extends md.BlockSyntax {
  static final _link = RegExp(
    '^ {0,3}(?:\\*\\*|\\*|__|_)?\\[[^\\]]+\\]\\([^)\\s]*/${SkillPage.apps.folder}/[^)\\s]*\\)',
  );

  @override
  RegExp get pattern => _link;

  @override
  bool canParse(md.BlockParser parser) =>
      parser.parentSyntax == null &&
      parser.current.content.contains(SkillPage.apps.folder) &&
      super.canParse(parser);

  /// Never ends the paragraph before it.
  @override
  bool canEndBlock(md.BlockParser parser) => false;

  @override
  md.Node? parse(md.BlockParser parser) {
    final paragraph = const md.ParagraphSyntax().parse(parser);
    return paragraph == null ? null : md.Element(appCardTag, [paragraph]);
  }
}

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

/// The [AppCard] a Markdown quote or an [appCardTag] paragraph makes, or null when it is not
/// one: its first line must open with a link, alone or inside bold or italics, to an apps-lean
/// page on [server]. Any other quote or paragraph, and a link in the middle of a sentence, stays
/// as written.
AppCard? appCardOf(md.Element block, Uri? server) {
  final children = block.children;
  if (children == null) return null;
  if (block.tag != 'blockquote' && block.tag != appCardTag) return null;
  if (children.firstOrNull case md.Element(tag: 'p', children: final inline?)) {
    return _cardOf(inline, children.skip(1), server);
  }
  return null;
}

/// A dash, colon or dot that joins a paragraph's link to the words after it.
final _joiner = RegExp(r'^[\s\-:\u00b7\u2013\u2014]+');

/// The card of a quote whose first paragraph holds [inline] and which goes on with [more].
AppCard? _cardOf(List<md.Node> inline, Iterable<md.Node> more, Uri? server) {
  final at = inline.indexWhere((n) => !(n is md.Text && n.text.trim().isEmpty));
  if (at < 0) return null;
  final link = _linkIn(inline[at]);
  final href = link?.attributes['href'];
  if (link == null || href == null) return null;
  if (skillLinkOf(href, server)?.$1 != SkillPage.apps) return null;
  final title = link.textContent.trim();
  if (title.isEmpty) return null;
  final rest = [
    inline
        .skip(at + 1)
        .map((n) => n.textContent)
        .join()
        .replaceFirst(_joiner, ''),
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

/// What an apps-lean page's Comment sends: the person's message about the app, as the page wrote
/// it, which names the app and what they picked on it, for the chat of the workspace the app is in.
typedef PageComment = ({String workspace, String message});

/// The comment a page posted, `{"comment": {workspace, message}}`, its message cut to
/// [commentMax] characters; null when it is not one or says nothing.
PageComment? pageCommentOf(Object? json) => switch (json) {
  {
    'comment': {
      'workspace': final String workspace,
      'message': final String message,
    },
  }
      when message.trim().isNotEmpty =>
    (workspace: workspace, message: clip(message.trim(), commentMax)),
  _ => null,
};

/// The most characters a [PageComment]'s message may take: room for the page's 1000 of the
/// person's words and its 5 picks.
const commentMax = 4000;

/// The text of [block], one entry for each item when it is a list.
Iterable<String> _textsOf(md.Node block) =>
    block is md.Element && (block.tag == 'ul' || block.tag == 'ol')
    ? [for (final item in block.children ?? const <md.Node>[]) item.textContent]
    : [block.textContent];
