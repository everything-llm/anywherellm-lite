// The documents Documents lists: the server's library, each with whether the active workspace
// answers from it.

import 'copy.dart';
import 'server_models.dart';
import 'upload.dart';

class SourceFile {
  const SourceFile({
    required this.path,
    required this.title,
    required this.on,
    this.words,
    this.web,
    this.pinned = false,
    this.link,
    this.fileName,
    this.published,
  });

  /// `folder/name.json`, how the workspace names it.
  final String path;
  final String title;

  /// Whether the workspace answers from it.
  final bool on;
  final int? words;

  /// Whether it is a web page, or null when the server did not say.
  final bool? web;

  /// Whether the workspace reads it whole with every answer (Read in full), which only one it
  /// answers from can.
  final bool pinned;

  /// The address a web page was read from, the file another document was read in from, and when
  /// the server read it in, as [LibraryDoc] has them.
  final String? link;
  final String? fileName;
  final String? published;

  /// The library folder it is in.
  String get folder => docFolder(path);

  /// The name the server stored it under, `<name>-<id>.json`, which moving it to another folder
  /// keeps.
  String get storedName => docName(path);

  /// The type on the file's tile: `PDF`, `MD`, `WEB` or `FILE`. A web page is `WEB`, and any
  /// other document takes the extension of the name it is stored under, so an upload called
  /// `URL-list.md` is `MD`. Only when the server did not say is a stored name starting `url-`
  /// taken for a web page.
  String get tile => _isWeb ? 'WEB' : sourceExt(_storedName(path));

  bool get _isWeb => web ?? _storedName(path).startsWith('url-');

  /// `1,204 words`, or empty when the server did not count them.
  String get size => words == null ? '' : plural(words!, 'word', 'words');

  /// The line under the file's name in Documents: [size], after `Not used` when it is
  /// switched off, and before `Read in full` when the workspace reads it whole.
  String get meta => _joined([if (!on) _notUsed, size, if (pinned) readInFull]);

  /// Where it came from, as Document details names it.
  DocOrigin get origin => _isWeb
      ? DocOrigin.web
      : _storedName(path).startsWith('raw-')
      ? DocOrigin.text
      : DocOrigin.file;

  /// What more [origin] says: the page's address, or the name of the file it was read in from,
  /// or null.
  String? get from => switch (origin) {
    DocOrigin.web => link,
    DocOrigin.file => fileName,
    DocOrigin.text => null,
  };

  /// When the server read it in, as [addedText] gives it, or null when it did not say.
  String? get added => published == null ? null : addedText(published!);
}

/// Where a document came from: a file, a web page, or text pasted in.
enum DocOrigin {
  file('Uploaded file'),
  web('Web page'),
  text('Pasted text');

  const DocOrigin(this.label);

  final String label;
}

/// What a switched-off document is marked.
const _notUsed = 'Not used';

/// What a document the workspace reads whole is marked, and what the switch for it is called.
const readInFull = 'Read in full';

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

/// The documents Documents lists: each in [library], folder by folder in the server's order, on
/// where the workspace has it [embedded], and read in full where the workspace pins it; then any
/// the workspace has that the library did not list, on. With no [library], as before it is read,
/// the workspace's documents alone.
List<SourceFile> librarySources(
  List<LibraryFolder>? library,
  List<WorkspaceDoc> embedded,
) {
  final used = {for (final doc in embedded) doc.path: doc};
  final listed = <String>{};
  return [
    for (final folder in library ?? const <LibraryFolder>[])
      for (final doc in folder.docs)
        if (listed.add(doc.path))
          SourceFile(
            path: doc.path,
            title: doc.title,
            on: used.containsKey(doc.path),
            words: doc.words ?? used[doc.path]?.words,
            web: doc.web ?? used[doc.path]?.web,
            pinned: used[doc.path]?.pinned ?? false,
            link: doc.link,
            fileName: doc.fileName,
            published: doc.published,
          ),
    for (final doc in embedded)
      if (!listed.contains(doc.path))
        SourceFile(
          path: doc.path,
          title: doc.title,
          on: true,
          words: doc.words,
          web: doc.web,
          pinned: doc.pinned,
        ),
  ];
}

/// [files] by their folder, each folder once in the order its first file comes, its files in
/// their order.
List<(String, List<SourceFile>)> byFolder(List<SourceFile> files) {
  final groups = <String, List<SourceFile>>{};
  for (final file in files) {
    groups.putIfAbsent(file.folder, () => []).add(file);
  }
  return [for (final MapEntry(:key, :value) in groups.entries) (key, value)];
}

final _monthFirst = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})\b');
final _dayFirst = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})\b');

/// [published], the server's own words for when it read a document in, as a date such as
/// `12 Oct 2026`. The server writes its clock's `toLocaleString`: an American one gives
/// `month/day/year`, read so unless the first number can be no month, and a German one
/// `day.month.year`; an ISO date is read too. Any other text is given as it is.
String addedText(String published) {
  final text = published.trim();
  if (DateTime.tryParse(text) case final at?) {
    final local = at.toLocal();
    return _date(local.year, local.month, local.day) ?? text;
  }
  if (_monthFirst.firstMatch(text) case final m?) {
    final (a, b) = (int.parse(m[1]!), int.parse(m[2]!));
    final year = int.parse(m[3]!);
    return (a > 12 ? _date(year, b, a) : _date(year, a, b)) ?? text;
  }
  if (_dayFirst.firstMatch(text) case final m?) {
    return _date(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!)) ?? text;
  }
  return text;
}

/// `12 Oct 2026`, or null when [month] or [day] is out of range.
String? _date(int year, int month, int day) =>
    month < 1 || month > 12 || day < 1 || day > 31
    ? null
    : '$day ${monthNames[month - 1]} $year';

/// Why [name] cannot be a new library folder, or null.
String? folderProblem(String name) {
  final folder = name.trim();
  if (folder.isEmpty) return 'Give the folder a name.';
  if (folder.contains('/') || folder.contains(r'\')) {
    return r'A folder name cannot hold / or \.';
  }
  if (folder.replaceAll('.', '').isEmpty) {
    return 'A folder name needs more than dots.';
  }
  return null;
}

/// How close a passage came to what was asked, as `82% match`, from the server's [score]
/// between 0 and 1.
String matchText(double score) => '${(score * 100).round()}% match';
