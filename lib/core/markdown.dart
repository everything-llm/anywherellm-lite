import 'package:markdown/markdown.dart' as md;

/// GitHub-flavoured Markdown as an answer is read. A bare address stops at a `]`, as on
/// GitHub, which links bare addresses only after links and images are read: so a card whose
/// description holds an address, `[![Browser: https://...](card.jpg)](page)`, stays an image
/// inside a link.
final answerMarkdown = md.ExtensionSet(
  md.ExtensionSet.gitHubFlavored.blockSyntaxes,
  [
    for (final syntax in md.ExtensionSet.gitHubFlavored.inlineSyntaxes)
      syntax is md.AutolinkExtensionSyntax ? _BoundedAutolink() : syntax,
  ],
);

/// `package:markdown`'s bare address, which ends before a `]`.
class _BoundedAutolink extends md.AutolinkExtensionSyntax {
  static final _pattern = RegExp(
    // The scheme or `www.`, a domain, then a path of anything but a space, `<` or `]` that
    // does not end in trailing punctuation.
    r'((?:(?:https?|ftp):\/\/|www\.)(?:[-_a-z0-9]+\.)*(?:[-a-z0-9]+\.[-a-z0-9]+)'
    r'[^\s<\]]*[^\s<?!.,:*_~\]])'
    // Or an email address.
    r'|([-_.+a-z0-9]+@(?:[-_a-z0-9]+\.)+[-_a-z0-9]*[a-z0-9])',
    multiLine: true,
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _pattern;
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
      } else if (node.textContent.trim() case final line when line.isNotEmpty) {
        lines.add(line);
      }
    }
  }

  walk(md.Document(extensionSet: answerMarkdown).parse(markdown));
  return lines.join('\n');
}

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
