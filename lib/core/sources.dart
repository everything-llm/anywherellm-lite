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
