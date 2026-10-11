/// A picture an answer shows: its [image], its [caption] (the image's description), and the
/// [page] it came from, the link around it, when it has one.
class Picture {
  const Picture(this.image, {this.caption = '', this.page});

  final Uri image;
  final String caption;
  final Uri? page;

  /// The site the picture came from: its page's host, or else its own.
  String get site => (page ?? image).host;

  /// The file name the picture saves under.
  String get fileName {
    final last = image.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
    return last ?? 'picture.jpg';
  }

  /// Whether the picture is a copy the server's image search made of one on the web.
  bool get fromWebSearch => image.path.startsWith('/_webimages/');

  @override
  bool operator ==(Object other) =>
      other is Picture &&
      other.image == image &&
      other.caption == caption &&
      other.page == page;

  @override
  int get hashCode => Object.hash(image, caption, page);
}

/// A run of an answer's Markdown: text, or a [GalleryPart].
sealed class AnswerPart {
  const AnswerPart();
}

/// Markdown drawn as it is.
class TextPart extends AnswerPart {
  const TextPart(this.markdown);

  final String markdown;
}

/// Two or more pictures in a row, with nothing between them but blank lines.
class GalleryPart extends AnswerPart {
  const GalleryPart(this.pictures);

  final List<Picture> pictures;
}

/// One image, alone or inside a link: `![caption](image)` or `[![caption](image)](page)`.
final _picture = RegExp(
  r'(?:\[!\[([^\]]*)\]\(([^)\s]+)\)\]\(([^)\s]+)\)|!\[([^\]]*)\]\(([^)\s]+)\))',
);

/// A line holding only images, with nothing but spaces between them.
final _pictureLine = RegExp('^\\s*(?:${_picture.pattern}\\s*)+\$');

/// Whether [image] is one of the everythingllm host's cards, a page's or a live one, which an
/// answer draws large and alone, never in a gallery.
bool isCardImage(Uri image) =>
    image.path.startsWith('/_cards/') || image.path.startsWith('/_live/');

/// The pictures on a line that holds only images, or null when it holds anything else or a
/// card.
List<Picture>? _picturesOn(String line) {
  if (!_pictureLine.hasMatch(line)) return null;
  final found = <Picture>[];
  for (final m in _picture.allMatches(line)) {
    final linked = m[2] != null;
    final image = Uri.tryParse(linked ? m[2]! : m[5]!);
    if (image == null || isCardImage(image)) return null;
    found.add(
      Picture(
        image,
        caption: (linked ? m[1] : m[4])?.trim() ?? '',
        page: linked ? Uri.tryParse(m[3]!) : null,
      ),
    );
  }
  return found;
}

/// The answer [markdown] cut into its text and its galleries: each run of two or more pictures
/// on lines of their own, outside code, is a [GalleryPart]. Blank lines inside a run belong to
/// it; those around it stay with the text.
List<AnswerPart> answerParts(String markdown) {
  if (!markdown.contains('![')) return [TextPart(markdown)];
  final lines = markdown.split('\n');
  final parts = <AnswerPart>[];
  final text = <String>[];
  String? fence;
  var i = 0;

  void flushText() {
    if (text.isEmpty) return;
    parts.add(TextPart(text.join('\n')));
    text.clear();
  }

  while (i < lines.length) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (fence != null) {
      if (trimmed.startsWith(fence)) fence = null;
      text.add(line);
      i++;
      continue;
    }
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      fence = trimmed.substring(0, 3);
      text.add(line);
      i++;
      continue;
    }
    final first = _picturesOn(line);
    if (first == null) {
      text.add(line);
      i++;
      continue;
    }
    // Gathers the run: picture lines, with blank lines between them.
    final pictures = [...first];
    var end = i + 1;
    var j = i + 1;
    while (j < lines.length) {
      if (lines[j].trim().isEmpty) {
        j++;
        continue;
      }
      final more = _picturesOn(lines[j]);
      if (more == null) break;
      pictures.addAll(more);
      end = ++j;
    }
    if (pictures.length < 2) {
      text.add(line);
      i++;
      continue;
    }
    flushText();
    parts.add(GalleryPart(pictures));
    i = end;
  }
  flushText();
  return parts;
}
