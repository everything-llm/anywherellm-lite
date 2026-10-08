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
    this.pinned = false,
  });

  /// `folder/name.json`, how the workspace names it.
  final String path;
  final String title;

  /// Whether the workspace answers from it.
  final bool on;
  final int? words;

  /// Whether its whole text is always in the workspace's context. Only a switched-on file can be.
  final bool pinned;

  /// The type on the file's tile: `PDF`, `MD`, `WEB` or `FILE`.
  String get tile => docType(path);

  /// `1,204 words`, or empty when the server did not count them.
  String get size => wordCount(words);

  /// The line under the file's name in Documents: [size], after `Not used` when it is
  /// switched off.
  String get meta =>
      on ? size : [notUsed, if (size.isNotEmpty) size].join(' · ');

  /// The line under the file's name in the Files pane: [size], before `Not used in answers`
  /// when it is switched off.
  String get filesMeta => on
      ? size
      : [if (size.isNotEmpty) size, '$notUsed in answers'].join(' · ');

  OffDoc get asOff => OffDoc(path: path, title: title, words: words);
}

/// What a switched-off document is marked.
const notUsed = 'Not used';

/// `1,204 words` for [words], or empty when the server did not count them.
String wordCount(int? words) =>
    words == null ? '' : '${grouped(words)} ${words == 1 ? 'word' : 'words'}';

/// [title] without the extension of the file it came from: `Q3 roadmap` for `Q3 roadmap.pdf`.
String shortTitle(String title) {
  final type = sourceExt(title);
  if (type == 'FILE') return title;
  final short = title.substring(0, title.length - extensionOf(title).length);
  return short.trim().isEmpty ? title : short;
}

/// What an empty chat offers to ask, built from the [titles] of the documents it answers
/// from, so it needs no model call: one to summarise the first, and with two or more one to
/// compare the first two. With none, the one question that needs no documents.
List<String> suggestionsFor(List<String> titles) {
  final names = [for (final t in titles) shortTitle(t)];
  return switch (names) {
    [] => const ['What can I do here?'],
    [final only] => ['Summarise $only'],
    [final first, final second, ...] => [
      'Summarise $first',
      'Compare $first with $second',
    ],
  };
}

final _storedId = RegExp(
  r'-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// The type of the document at [path], read from the name the server stored it under rather than
/// its title: `report.pdf-<id>.json` is `PDF`, and a web page's `url-<page>-<id>.json` is `WEB`.
String docType(String path) {
  var name = docName(path);
  if (name.endsWith('.json')) name = name.substring(0, name.length - 5);
  name = name.replaceFirst(_storedId, '');
  return name.startsWith('url-') ? 'WEB' : sourceExt(name);
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
        pinned: doc.pinned,
      ),
    for (final doc in off)
      if (!onPaths.contains(doc.path))
        SourceFile(
          path: doc.path,
          title: doc.title,
          on: false,
          words: doc.words,
        ),
  ];
}
