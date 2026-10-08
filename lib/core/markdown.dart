import 'package:markdown/markdown.dart' as md;

/// GitHub-flavoured Markdown as an answer is read, TeX included ([mathSyntaxes]). A bare
/// address stops at a `]` it did not open, as on GitHub, which links bare addresses only after
/// links and images are read: so a card whose description holds an address,
/// `[![Browser: https://...](card.jpg)](page)`, stays an image inside a link, and
/// `https://x.example/?ids[]=1` stays one address.
final answerMarkdown = md.ExtensionSet(
  md.ExtensionSet.gitHubFlavored.blockSyntaxes,
  [
    ...mathSyntaxes,
    for (final syntax in md.ExtensionSet.gitHubFlavored.inlineSyntaxes)
      syntax is md.AutolinkExtensionSyntax ? _BoundedAutolink() : syntax,
  ],
);

/// [text] parsed as an answer is drawn, with its characters left unescaped.
List<md.Node> parseAnswer(String text) =>
    md.Document(extensionSet: answerMarkdown, encodeHtml: false).parse(text);

/// Each image in the answer [text] that sits inside a link, in order: its address, its
/// description, and the address of the link around it.
List<({Uri image, String alt, Uri link})> linkedImagesIn(String text) {
  if (!text.contains('![')) return const [];
  final found = <({Uri image, String alt, Uri link})>[];
  void visit(md.Node node, Uri? link) {
    if (node is! md.Element) return;
    if (node.tag == 'img' && link != null) {
      if (Uri.tryParse(node.attributes['src'] ?? '') case final image?) {
        found.add((
          image: image,
          alt: node.attributes['alt'] ?? '',
          link: link,
        ));
      }
    }
    final href = node.tag == 'a'
        ? Uri.tryParse(node.attributes['href'] ?? '')
        : null;
    for (final child in node.children ?? const <md.Node>[]) {
      visit(child, href ?? link);
    }
  }

  for (final node in parseAnswer(text)) {
    visit(node, null);
  }
  return found;
}

/// `package:markdown`'s bare address, cut before a `]` that closes no `[` of its own.
class _BoundedAutolink extends md.AutolinkExtensionSyntax {
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    if (match[1] != null) {
      final address = match[0]!;
      var depth = 0;
      for (var i = 0; i < address.length; i++) {
        if (address[i] == '[') {
          depth++;
        } else if (address[i] == ']') {
          if (depth == 0) {
            // Matched again on what comes before the `]`, so trailing punctuation is left out
            // as it is from any address.
            final cut = pattern.matchAsPrefix(
              match.input.substring(0, match.start + i),
              match.start,
            );
            return cut != null && super.onMatch(parser, cut);
          }
          depth--;
        }
      }
    }
    return super.onMatch(parser, match);
  }
}

/// The syntaxes that make TeX in an answer a `math` element, whose `display` attribute says
/// whether it stands on its own: `$$...$$` and `\[...\]` do, `$...$` and `\(...\)` sit in the
/// text. A dollar pair is math only as pandoc reads it: the opening `$` has no space after it,
/// and the closing `$` has no space before it and no digit after it, so prices such as
/// "$5 and $10" stay text. Each is tried only where its first character is.
final mathSyntaxes = <md.InlineSyntax>[
  _MathSyntax(
    r'\$\$([\s\S]+?)\$\$|\$(?!\s)((?:\\.|[^$\\\n])+?)(?<!\s)\$(?!\d)',
    0x24, // $
  ),
  _MathSyntax(r'\\\[([\s\S]+?)\\\]|\\\(([\s\S]+?)\\\)', 0x5C), // \
];

/// One of [mathSyntaxes]: its first group is display math, its second math in the text.
class _MathSyntax extends md.InlineSyntax {
  _MathSyntax(super.pattern, int start) : super(startCharacter: start);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final display = match[1] != null;
    parser.addNode(
      md.Element.text('math', (match[1] ?? match[2])!.trim())
        ..attributes['display'] = '$display',
    );
    return true;
  }
}

/// [markdown] as the words a person would read: no markup, a link as its text, and each block
/// on its own line.
String plainText(String markdown) {
  final lines = <String>[];
  void walk(List<md.Node> nodes) {
    for (final node in nodes) {
      if (node is md.Element &&
          _holdsBlocks.contains(node.tag) &&
          (node.children ?? const []).any(
            (child) => child is md.Element && _blocks.contains(child.tag),
          )) {
        walk(node.children ?? const []);
      } else if (_textOf(node).trim() case final line when line.isNotEmpty) {
        lines.add(line);
      }
    }
  }

  walk(parseAnswer(markdown));
  return lines.join('\n');
}

/// [node]'s words, with a table row's cells apart.
String _textOf(md.Node node) => node is md.Element && node.tag == 'tr'
    ? [
        for (final cell in node.children ?? const <md.Node>[])
          if (cell.textContent.trim() case final text when text.isNotEmpty)
            text,
      ].join(', ')
    : node.textContent;

/// The Markdown elements that start a line of their own.
const _blocks = {
  ..._holdsBlocks,
  'p',
  'pre',
  'tr',
  'hr',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
};

/// The Markdown elements made of other blocks, whose blocks are each read as a line. One that
/// holds only text, such as a list item of a few words, is read as one line.
const _holdsBlocks = {
  'ul',
  'ol',
  'li',
  'blockquote',
  'table',
  'thead',
  'tbody',
};
