/// Something another app shared with AnywhereLLM through the system's share sheet.
sealed class SharedItem {
  const SharedItem();
}

/// A web page, by its [url], with the [title] the sharing app gave it, if any.
class SharedLink extends SharedItem {
  const SharedLink(this.url, {this.title});

  final Uri url;
  final String? title;
}

/// Text the person selected and shared.
class SharedText extends SharedItem {
  const SharedText(this.text);

  final String text;
}

/// A file called [name], [size] bytes long, whose bytes [read] gives.
class SharedFile extends SharedItem {
  const SharedFile(this.name, this.size, this.read);

  final String name;
  final int size;
  final Future<List<int>> Function() read;
}

/// What shared [text] holds: a link when it is an address alone, or a title over one, and the
/// text itself otherwise.
SharedItem sharedTextItem(String text) {
  final lines = [
    for (final line in text.trim().split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  if (lines.isEmpty || lines.length > 2) return SharedText(text.trim());
  final url = Uri.tryParse(lines.last);
  final web =
      url != null &&
      (url.scheme == 'http' || url.scheme == 'https') &&
      url.host.isNotEmpty &&
      !lines.last.contains(' ');
  if (!web) return SharedText(text.trim());
  return SharedLink(url, title: lines.length == 2 ? lines.first : null);
}
