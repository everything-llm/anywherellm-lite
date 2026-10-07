import 'package:markdown/markdown.dart' as md;

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

  walk(
    md.Document(extensionSet: md.ExtensionSet.gitHubFlavored).parse(markdown),
  );
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
