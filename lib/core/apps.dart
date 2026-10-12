import 'dart:convert';
import 'dart:typed_data';

import 'copy.dart';

export 'app_history.dart';

/// What `GET /health` on the apps server's port names itself, which tells it from anything
/// else that might answer there.
const appsService = 'anythingllm-apps-v2';

/// The port of the apps server's cards and client API, beside AnythingLLM on the same host.
const appsCardsPort = 8466;

/// The port of the apps server's working pages.
const appsPagesPort = 8465;

/// Whether [json], the answer to `GET /health`, is the apps server's.
bool isAppsHealth(Object? json) =>
    json is Map && json['service'] == appsService;

/// The apps server's client API beside the AnythingLLM server at [server]: the same host on
/// [appsCardsPort], over https.
Uri appsBase(Uri server) =>
    Uri(scheme: 'https', host: server.host, port: appsCardsPort);

/// One app of a workspace, by the workspace's slug and the app's folder name.
class AppRef {
  const AppRef(this.workspace, this.name);

  final String workspace;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is AppRef && other.workspace == workspace && other.name == name;

  @override
  int get hashCode => Object.hash(workspace, name);

  @override
  String toString() => 'apps/$workspace/$name';
}

final _appName = RegExp(r'^[a-z0-9-]{1,63}$');

/// The app whose live card is at [url], on the apps server beside [server]
/// (`https://<host>:8466/cards/<workspace>/<name>.png`), or null for any other address.
AppRef? appCardRef(Uri url, Uri? server) {
  if (!_onAppsHost(url, server, appsCardsPort)) return null;
  final parts = url.pathSegments;
  if (parts.length != 3 || parts[0] != 'cards' || !parts[2].endsWith('.png')) {
    return null;
  }
  return _ref(parts[1], parts[2].substring(0, parts[2].length - 4));
}

/// The app whose working page is at [url], on the apps server beside [server]
/// (`https://<host>:8465/<workspace>/<name>/`), or null for any other address.
AppRef? appPageRef(Uri url, Uri? server) {
  if (!_onAppsHost(url, server, appsPagesPort)) return null;
  final parts = [
    for (final part in url.pathSegments)
      if (part.isNotEmpty) part,
  ];
  return parts.length == 2 ? _ref(parts[0], parts[1]) : null;
}

/// The app [url] names, as its card or its page, or null.
AppRef? appRefOf(Uri url, Uri? server) =>
    appCardRef(url, server) ?? appPageRef(url, server);

bool _onAppsHost(Uri url, Uri? server, int port) =>
    server != null &&
    url.scheme == 'https' &&
    url.host == server.host &&
    url.port == port;

AppRef? _ref(String workspace, String name) =>
    workspace.isNotEmpty && _appName.hasMatch(name)
    ? AppRef(workspace, name)
    : null;

/// The card at [card] as one plain picture (`once=1`), drawn light when [light], dark
/// otherwise. The plain address streams a new picture each time the app changes, which an
/// answer's image reader would never finish reading.
Uri onceCard(Uri card, {required bool light}) =>
    card.replace(queryParameters: {'once': '1', if (light) 'theme': 'light'});

/// An app's card as last read: the picture, and the `ETag` it came with (`"<version>-<theme>"`),
/// which the next read sends back so that an unchanged card is not sent again. An apps server
/// that sends no `ETag` leaves [etag] null, and each read then fetches the picture.
class CardPicture {
  const CardPicture(this.bytes, {this.etag});

  final Uint8List bytes;
  final String? etag;
}

/// [page] with `theme` set to the app's own, so the page keeps to it whatever the device's.
Uri themedPage(Uri page, {required bool dark}) => page.replace(
  queryParameters: {...page.queryParameters, 'theme': dark ? 'dark' : 'light'},
);

/// The working page of [ref] on the apps server beside [server].
Uri appPage(Uri server, AppRef ref) => Uri(
  scheme: 'https',
  host: server.host,
  port: appsPagesPort,
  pathSegments: [ref.workspace, ref.name, ''],
);

/// The starter an app was made from, in words: `list` is List, `pomodoro` is Timer.
String kindLabel(String? kind) => switch (kind) {
  null || '' => 'App',
  'list' => 'List',
  'tracker' => 'Tracker',
  'pomodoro' => 'Timer',
  'flashcards' => 'Deck',
  'calendar' => 'Calendar',
  'blank' => 'Blank',
  'custom' => 'Custom',
  final other => other[0].toUpperCase() + other.substring(1),
};

/// A time in seconds since 1970, as the apps server sends it, or null.
DateTime? _seconds(Object? value) => value is num
    ? DateTime.fromMillisecondsSinceEpoch((value * 1000).round(), isUtc: true)
    : null;

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

Uri? _uri(Object? value) => value is String ? Uri.tryParse(value) : null;

/// An app as the apps server lists it.
class ServerApp {
  const ServerApp({
    required this.ref,
    required this.title,
    this.kind,
    this.summary = '',
    this.modified,
    this.line,
    this.restorableFrom,
    this.version,
    this.page,
    this.card,
    this.error,
  });

  /// One entry of `GET /apps/<workspace>`'s `apps`, or `GET /apps/<workspace>/<name>`'s
  /// answer, or null when it names no app.
  static ServerApp? fromJson(String workspace, Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || !_appName.hasMatch(name)) return null;
    return ServerApp(
      ref: AppRef(workspace, name),
      title: _text(json['title']) ?? name,
      kind: _text(json['kind']),
      summary: json['summary'] is String ? json['summary'] as String : '',
      modified: _seconds(json['modified']),
      line: json['line'] is int ? json['line'] as int : null,
      restorableFrom: json['restorable_from'] is int
          ? json['restorable_from'] as int
          : null,
      version: _text(json['version']),
      page: _uri(json['page']),
      card: _uri(json['card']),
      error: _text(json['error']),
    );
  }

  /// A stand-in for [ref] before its workspace's apps are read, titled by its folder name.
  factory ServerApp.unread(AppRef ref, Uri server) =>
      ServerApp(ref: ref, title: ref.name, page: appPage(server, ref));

  final AppRef ref;
  final String title;

  /// The starter it was made from, such as `list`, or `custom`; null when its folder could not
  /// be read.
  final String? kind;

  /// The line above the card's title, such as `1 of 2 left`.
  final String summary;

  /// When its newest log line was appended.
  final DateTime? modified;

  /// How many lines its log holds.
  final int? line;

  /// The first line its `log.jsonl` holds: 1, or the line a compaction left. The app can be
  /// put back only to a line from this one on. Null from an apps server that does not say.
  final int? restorableFrom;

  /// `<line>-<newest commit>`, which changes whenever its data, `app.json` or `page.html`
  /// does. Null for an app that cannot be read, or from an apps server that does not say.
  final String? version;

  /// Its working page.
  final Uri? page;

  /// Its live card.
  final Uri? card;

  /// Why its folder could not be read, when it could not.
  final String? error;

  /// Its kind in words, then its summary: `List · 1 of 2 left`.
  String about(DateTime now) => [
    kindLabel(kind),
    if (error != null) 'Cannot be read' else if (summary.isNotEmpty) summary,
    if (modified case final at?) whenShort(at, now),
  ].join(' · ');

  /// Whether [other] shows the same data, so its card need not be read again: the same
  /// [version] when both have one, otherwise the same title, line count, time and summary.
  bool sameAs(ServerApp other) => version != null && other.version != null
      ? other.version == version
      : other.title == title &&
            other.line == line &&
            other.modified == modified &&
            other.summary == summary;
}

/// `GET /apps/<workspace>`'s apps, newest change first.
List<ServerApp> appsOf(String workspace, Object? json) {
  final list = json is Map ? json['apps'] : null;
  return appsInOrder([
    if (list is List)
      for (final entry in list) ?ServerApp.fromJson(workspace, entry),
  ]);
}

/// [apps] newest change first, sorted in place.
List<ServerApp> appsInOrder(List<ServerApp> apps) {
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return apps
    ..sort((a, b) => (b.modified ?? epoch).compareTo(a.modified ?? epoch));
}

/// When [at] was, short, in local time from [now]: `Today 08:14`, `Yesterday 20:30`,
/// `9 Oct 07:40`.
String whenShort(DateTime at, DateTime now) {
  final local = at.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final days = today
      .difference(DateTime(local.year, local.month, local.day))
      .inDays;
  final time = clockText(local);
  return switch (days) {
    0 => 'Today $time',
    1 => 'Yesterday $time',
    _ => '${local.day} ${monthNames[local.month - 1]} $time',
  };
}

/// The day [at] falls on, in local time from [now], as the log's headings say it: `Today`,
/// `Yesterday` or `9 Oct`.
String dayText(DateTime at, DateTime now) {
  final local = at.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final days = today
      .difference(DateTime(local.year, local.month, local.day))
      .inDays;
  return switch (days) {
    0 => 'Today',
    1 => 'Yesterday',
    _ => '${local.day} ${monthNames[local.month - 1]}',
  };
}

/// A file of an app's folder, as `GET .../files` lists it. Caches and git are never listed.
class AppFile {
  const AppFile(this.path, {this.size = 0, this.modified});

  final String path;
  final int size;
  final DateTime? modified;
}

/// `GET .../files`'s files, by path.
List<AppFile> appFilesOf(Object? json) {
  final list = json is Map ? json['files'] : null;
  final files = [
    if (list is List)
      for (final entry in list)
        if (entry is Map && entry['path'] is String)
          AppFile(
            entry['path'] as String,
            size: entry['size'] is int ? entry['size'] as int : 0,
            modified: _seconds(entry['modified']),
          ),
  ];
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// A size in bytes, short: `812 B`, `1.7 KB`, `2.4 MB`.
String bytesText(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

/// [json] as indented JSON, two spaces a level.
String prettyJson(Object? json) =>
    const JsonEncoder.withIndent('  ').convert(json);
