/// Something another app shared with AnywhereLLM through the system's share sheet, or a link
/// it opened in AnywhereLLM.
sealed class SharedItem {
  const SharedItem();
}

/// A pairing link, `anywherellm://connect?...`, whole in [code], which a
/// tapped link or a share hands over. It is offered to connect with, never added or asked about.
class SharedPairing extends SharedItem {
  const SharedPairing(this.code);

  final String code;
}

/// What can be added to a workspace's documents or asked about: a link, text or a file.
sealed class SharedContent extends SharedItem {
  const SharedContent();
}

/// A web page, by its [url], with the [title] the sharing app gave it, if any.
class SharedLink extends SharedContent {
  const SharedLink(this.url, {this.title});

  final Uri url;
  final String? title;
}

/// Text the person selected and shared.
class SharedText extends SharedContent {
  const SharedText(this.text);

  final String text;
}

/// A file called [name], [size] bytes long, whose bytes [read] gives.
class SharedFile extends SharedContent {
  const SharedFile(this.name, this.size, this.read);

  final String name;
  final int size;
  final Future<List<int>> Function() read;
}

final _space = RegExp(r'\s');

/// What shared [text] holds: a pairing link when it is one alone, a link when it is an address
/// alone, or a title over one, and the text itself otherwise.
SharedItem sharedTextItem(String text) {
  final trimmed = text.trim();
  if (trimmed.startsWith('anywherellm:') && !trimmed.contains(_space)) {
    return SharedPairing(trimmed);
  }
  final lines = [
    for (final line in trimmed.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  if (lines.isEmpty || lines.length > 2) return SharedText(trimmed);
  final url = Uri.tryParse(lines.last);
  final web =
      url != null &&
      (url.scheme == 'http' || url.scheme == 'https') &&
      url.host.isNotEmpty &&
      !lines.last.contains(' ');
  if (!web) return SharedText(trimmed);
  return SharedLink(url, title: lines.length == 2 ? lines.first : null);
}
