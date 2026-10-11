import 'activity.dart';
import 'host_routes.dart';
import 'outputs.dart';

/// Where in the workspace's sandbox a created file is.
enum CreatedArea {
  /// Kept: the agent's `/project`, with the browser's downloads in `project/downloads`.
  project,

  /// A working file of one chat, which goes a week after the chat last used the sandbox.
  work,

  /// On the web, at the workspace's pages site.
  public,

  /// Other workspaces can read it.
  shared;

  static CreatedArea? named(Object? name) => values.asNameMap()[name];
}

/// Something the agent left in a workspace's sandbox that the host lists and deletes: a
/// [CreatedFile] or a [CreatedApp]. Its [id] is the one thing the host's other calls take.
sealed class Created {
  const Created();

  String get id;

  /// What the person calls it: a file's name, an app's title.
  String get label;
}

/// One file the agent's code left in a workspace's sandbox, as the everythingllm host lists it.
class CreatedFile extends Created {
  const CreatedFile({
    required this.id,
    required this.name,
    required this.dir,
    required this.size,
    required this.modified,
    required this.area,
    this.expires,
    this.url,
  });

  @override
  final String id;
  final String name;

  @override
  String get label => name;

  /// The folder the file is in, inside its area, or empty.
  final String dir;
  final int size;
  final DateTime modified;
  final CreatedArea area;

  /// When a working file goes, unless it is kept.
  final DateTime? expires;

  /// Where a file on the web is, on the pages site.
  final String? url;

  /// Whether the file is a web page, which Open page shows.
  bool get isPage =>
      area == CreatedArea.public && url != null && _page.hasMatch(name);

  static final _page = RegExp(r'\.html?$', caseSensitive: false);

  /// Whether the browser downloaded the file: the host keeps its downloads in `project/downloads`.
  bool get fromBrowser =>
      area == CreatedArea.project &&
      (dir == 'downloads' || dir.startsWith('downloads/'));

  /// The file as the host lists it, or null for one that lacks what the app needs.
  static CreatedFile? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final size = json['size'];
    final modified = json['modified'];
    final area = CreatedArea.named(json['area']);
    if (id is! String ||
        name is! String ||
        size is! num ||
        modified is! num ||
        area == null) {
      return null;
    }
    final expires = json['expires'];
    final url = json['url'];
    return CreatedFile(
      id: id,
      name: name,
      dir: json['dir'] is String ? json['dir'] as String : '',
      size: size.toInt(),
      modified: _seconds(modified),
      area: area,
      expires: expires is num ? _seconds(expires) : null,
      url: url is String && url.isNotEmpty ? url : null,
    );
  }

  static DateTime _seconds(num seconds) =>
      DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
}

/// One of a workspace's apps, as the everythingllm host lists it beside the created files: an
/// app's page and the data it keeps, which the agent makes with its app skill. Its [id] is
/// `apps/<name>`.
class CreatedApp extends Created {
  const CreatedApp({
    required this.id,
    required this.name,
    required this.title,
    required this.modified,
    this.kind,
    this.summary = '',
    this.page,
    this.card,
    this.link,
    this.error,
  });

  @override
  final String id;

  /// Its name in the workspace, as its card's address has it.
  final String name;
  final String title;

  /// When its data last changed.
  final DateTime modified;

  /// The starter it was made from, such as `list`; null for an app the agent wrote whole, or
  /// one made before the host kept it.
  final String? kind;

  /// A line about it now, such as `4 of 6 left`.
  final String summary;

  /// Its page on the web, its live card, and where the card leads, which opens the page.
  final Uri? page;
  final Uri? card;
  final Uri? link;

  /// Why its data could not be read; such an app can still be deleted.
  final String? error;

  @override
  String get label => title;

  static const _kinds = {
    'list': 'List',
    'tracker': 'Tracker',
    'pomodoro': 'Timer',
    'flashcards': 'Deck',
    'calendar': 'Calendar',
  };

  /// The line under its title: its kind in words and how it stands, or why it cannot be read.
  String get about =>
      error ?? [?_kinds[kind], if (summary.isNotEmpty) summary].join(' · ');

  /// The app as the host lists it, or null for something that is not one.
  static CreatedApp? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final title = json['title'];
    final modified = json['modified'];
    if (id is! String || name is! String || title is! String) return null;
    Uri? uri(String key) =>
        json[key] is String ? Uri.tryParse(json[key] as String) : null;
    return CreatedApp(
      id: id,
      name: name,
      title: title,
      modified: CreatedFile._seconds(modified is num ? modified : 0),
      kind: json['kind'] is String ? json['kind'] as String : null,
      summary: json['summary'] is String ? json['summary'] as String : '',
      page: uri('page'),
      card: uri('card'),
      link: uri('link'),
      error: json['error'] is String ? json['error'] as String : null,
    );
  }
}

/// A workspace's created files, newest first, with how much of the workspace's room they and
/// the rest of its sandbox use.
class CreatedList {
  const CreatedList({
    this.files = const [],
    this.apps,
    this.used = 0,
    this.warn = 0,
    this.limit = 0,
    this.truncated = false,
  });

  final List<CreatedFile> files;

  /// The workspace's apps, last changed first, or null from a host that does not list them.
  final List<CreatedApp>? apps;

  /// Bytes the whole workspace uses: its files, its packages and the like.
  final int used;

  /// The size at which the host warns, and the one at which it stops the workspace.
  final int warn;
  final int limit;

  /// Whether the host left older files out of [files].
  final bool truncated;

  /// The list as the host answers, or null for something that is not one.
  static CreatedList? fromJson(Object? json) {
    if (json is! Map || json['files'] is! List) return null;
    int number(String key) => json[key] is num ? (json[key] as num).toInt() : 0;
    return CreatedList(
      files: [
        for (final entry in json['files'] as List) ?CreatedFile.fromJson(entry),
      ],
      apps: json['apps'] is List
          ? [
              for (final entry in json['apps'] as List)
                ?CreatedApp.fromJson(entry),
            ]
          : null,
      used: number('used'),
      warn: number('warn'),
      limit: number('limit'),
      truncated: json['truncated'] == true,
    );
  }

  /// How much of the room is used, from 0 to 1, or 0 when the host gave no limit.
  double get fraction =>
      limit <= 0 ? 0 : (used / limit).clamp(0.0, 1.0).toDouble();

  /// Whether the workspace is past the size at which the host warns.
  bool get nearFull => warn > 0 && used >= warn;

  /// How much is used, of the limit when the host gave one: `1.2 GB of 5.0 GB`.
  String get usedText =>
      limit > 0 ? '${sizeText(used)} of ${sizeText(limit)}' : sizeText(used);
}

/// What marks a file in the list, said only when it differs from a kept file: when a working
/// file goes, that it is on the web, or that other workspaces can read it. Null for a kept file.
String? createdMark(CreatedFile file, DateTime now) => switch (file.area) {
  CreatedArea.project => null,
  CreatedArea.public => 'On the web',
  CreatedArea.shared => 'Other workspaces can read',
  CreatedArea.work => switch (file.expires) {
    final expires? => _goes(expires.difference(now)),
    null => 'Goes after a week',
  },
};

/// The line under a file's name: for a page `Page` and its address, which holds its folder, or
/// `Published page` alone without [address]; for any other file its size, then where it came
/// from, the browser or its folder; then how long ago it changed.
String createdMeta(CreatedFile file, DateTime now, {bool address = true}) => [
  if (file.isPage)
    address ? 'Page · ${file.url!.replaceFirst(_scheme, '')}' : 'Published page'
  else ...[
    sizeText(file.size),
    if (file.fromBrowser)
      'downloaded by the browser'
    else if (file.dir.isNotEmpty)
      file.dir,
  ],
  agoText(file.modified, now),
].join(' · ');

final _scheme = RegExp(r'^https?://');

/// What is asked before [item] is deleted.
String deleteCreatedQuestion(Created item) => switch (item) {
  CreatedFile(:final name) =>
    'Delete $name from the workspace? It cannot be got back.',
  CreatedApp(:final title) =>
    'Delete $title? Its data goes with it, and its card in a chat says it was deleted.',
};

String _goes(Duration left) {
  if (left <= Duration.zero) return 'Goes soon';
  final days = (left.inHours / 24).ceil();
  return days <= 1 ? 'Goes in 1 day' : 'Goes in $days days';
}

/// The host's route for a workspace's created files, `/_live/sandbox/files/WORKSPACE`, with
/// [tail] after it, as `/download`, and the created file [path] it is about, when it has one.
Uri createdRoute(Uri server, String slug, [String tail = '', String? path]) =>
    liveRoute(
      server,
      'sandbox/files/${Uri.encodeComponent(slug)}$tail',
      path == null ? null : {'path': path},
    );
