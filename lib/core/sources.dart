// A workspace's documents: the ones it answers from, and the ones switched off.

import 'copy.dart';
import 'prefs.dart';
import 'server_models.dart';
import 'upload.dart';

class SourceFile {
  const SourceFile({
    required this.path,
    required this.title,
    required this.on,
    this.words,
    this.web,
  });

  /// `folder/name.json`, how the workspace names it.
  final String path;
  final String title;

  /// Whether the workspace answers from it.
  final bool on;
  final int? words;

  /// Whether it is a web page, or null when the server did not say.
  final bool? web;

  /// The type on the file's tile: `PDF`, `MD`, `WEB` or `FILE`. A web page is `WEB`, and any
  /// other document takes the extension of the name it is stored under, so an upload called
  /// `URL-list.md` is `MD`. Only when the server did not say is a stored name starting `url-`
  /// taken for a web page.
  String get tile {
    final name = _storedName(path);
    return (web ?? name.startsWith('url-')) ? 'WEB' : sourceExt(name);
  }

  /// `1,204 words`, or empty when the server did not count them.
  String get size => words == null ? '' : plural(words!, 'word', 'words');

  /// The line under the file's name in Documents: [size], after `Not used` when it is
  /// switched off.
  String get meta => on ? size : _joined([_notUsed, size]);

  OffDoc get asOff => OffDoc(path: path, title: title, words: words, web: web);
}

/// What a switched-off document is marked.
const _notUsed = 'Not used';

/// The [parts] that are not empty, with dots between them.
String _joined(List<String> parts) =>
    parts.where((part) => part.isNotEmpty).join(' · ');

/// [title] without the extension of the file it came from: `Q3 roadmap` for `Q3 roadmap.pdf`.
String shortTitle(String title) {
  final type = sourceExt(title);
  if (type == 'FILE') return title;
  final short = title.substring(0, title.length - extensionOf(title).length);
  return short.trim().isEmpty ? title : short;
}

/// One question an empty chat offers: the [label] its button shows, and the [prompt] it puts in
/// the message, which names each document in full.
typedef Suggestion = ({String label, String prompt});

/// The most characters a document's name takes in a suggestion's label.
const suggestionNameMax = 40;

/// [title] as a suggestion's label names it: [shortTitle], less a subtitle after a colon, cut at
/// a word to [suggestionNameMax] characters with an ellipsis, and whether it was cut.
({String name, bool cut}) _labelName(String title) {
  var name = shortTitle(title).trim();
  final colon = name.indexOf(': ');
  if (colon >= 3) name = name.substring(0, colon).trim();
  if (name.length <= suggestionNameMax) return (name: name, cut: false);
  final head = name.substring(0, suggestionNameMax);
  final space = head.lastIndexOf(' ');
  final kept = space >= 12 ? head.substring(0, space) : head;
  return (name: '${kept.trimRight()}\u2026', cut: true);
}

/// What an empty chat offers to ask, built from the [titles] of the documents it answers
/// from, so it needs no model call: one to summarise the first, and with two or more one to
/// compare the first two. With none, the one question that needs no documents. A label names a
/// long document by its start, and a comparison names the two only when both together fit in
/// [suggestionNameMax] characters.
List<Suggestion> suggestionsFor(List<String> titles) {
  final names = [for (final t in titles) shortTitle(t)];
  final labels = [for (final t in titles.take(2)) _labelName(t)];
  return switch (names) {
    [] => const [(label: 'What can I do here?', prompt: 'What can I do here?')],
    [final only] => [
      (label: 'Summarise ${labels[0].name}', prompt: 'Summarise $only'),
    ],
    [final first, final second, ...] => [
      (label: 'Summarise ${labels[0].name}', prompt: 'Summarise $first'),
      (
        label:
            labels[0].cut ||
                labels[1].cut ||
                labels[0].name.length + labels[1].name.length >
                    suggestionNameMax
            ? 'Compare the first two documents'
            : 'Compare ${labels[0].name} with ${labels[1].name}',
        prompt: 'Compare $first with $second',
      ),
    ],
  };
}

final _storedId = RegExp(
  r'-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// The name the server stored the document at [path] under, less its `.json` and id:
/// `report.pdf` for `report.pdf-<id>.json`.
String _storedName(String path) {
  var name = docName(path);
  if (name.endsWith('.json')) name = name.substring(0, name.length - 5);
  return name.replaceFirst(_storedId, '');
}

/// The documents [embedded] in a workspace, switched on, followed by those switched [off] there.
/// A document both embedded and remembered as off counts as on: the server has the last word.
List<SourceFile> mergeSources(List<WorkspaceDoc> embedded, List<OffDoc> off) {
  final onPaths = {for (final doc in embedded) doc.path};
  return [
    for (final doc in embedded)
      SourceFile(
        path: doc.path,
        title: doc.title,
        on: true,
        words: doc.words,
        web: doc.web,
      ),
    for (final doc in off)
      if (!onPaths.contains(doc.path))
        SourceFile(
          path: doc.path,
          title: doc.title,
          on: false,
          words: doc.words,
          web: doc.web,
        ),
  ];
}
