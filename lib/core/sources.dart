// A workspace's Sources: the documents it answers from, and the ones switched off.

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
  });

  /// `folder/name.json`, how the workspace names it.
  final String path;
  final String title;

  /// Whether the workspace answers from it.
  final bool on;
  final int? words;

  /// The type on the file's tile: `PDF`, `MD`, `WEB` or `FILE`.
  String get tile => docType(path);

  /// `1204 words`, or empty when the server did not count them.
  String get meta => words == null ? '' : plural(words!, 'word', 'words');

  OffDoc get asOff => OffDoc(path: path, title: title, words: words);
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
      SourceFile(path: doc.path, title: doc.title, on: true, words: doc.words),
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
