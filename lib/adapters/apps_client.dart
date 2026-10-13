import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/apps.dart';
import '../core/connection.dart';
import '../core/ports.dart';
import '../core/push.dart';
import '../core/system_files.dart';
import 'companion_client.dart';

/// [AppsApi] over the apps server's client API, on the AnythingLLM server's host at
/// [appsCardsPort], with the connection's developer key on every `/apps/` and `/system/`
/// call.
///
/// Every call reads the connection from the holder when it is made, and goes over https only.
/// An error message never contains the key.
class HttpAppsApi implements AppsApi {
  HttpAppsApi({
    required this._holder,
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
    Duration healthTimeout = const Duration(seconds: 5),
  }) : _companion = CompanionClient(
         appsCompanion,
         holder: _holder,
         client: client ?? http.Client(),
         timeout: timeout,
         healthTimeout: healthTimeout,
       );

  final ConnectionHolder _holder;
  final CompanionClient _companion;

  /// The routes an older apps server answered as unknown, by the address of the AnythingLLM
  /// server beside it and the route's kind (`app`, `log`), so they are not asked again until
  /// [available] asks again.
  final _missing = <String>{};

  @override
  Companion get companion => _companion.companion;

  @override
  Future<Uri?> pages() async {
    final named = switch (await _companion.health()) {
      {'pages': final String pages} => Uri.tryParse(pages),
      _ => null,
    };
    if (named != null && keySafe(named)) return named;
    final server = _holder.current;
    return server == null ? null : appPagesGuess(server.uri);
  }

  @override
  Future<Set<String>?> features({bool again = false}) {
    if (again) {
      final key = _holder.current?.baseUrl;
      _missing.removeWhere((missing) => missing.startsWith('$key '));
    }
    return _companion.features(again: again);
  }

  @override
  Future<String> pushKey() async {
    final body = await _json('GET', ['key'], root: 'push');
    final key = body is Map ? body['key'] : null;
    if (key is! String || key.isEmpty) {
      throw const ApiException('The apps server has no key for notifications.');
    }
    return key;
  }

  @override
  Future<void> subscribePush(PushSubscription subscription) =>
      _json('POST', ['subscribe'], root: 'push', body: subscription.toJson());

  @override
  Future<void> unsubscribePush(String endpoint) => _json(
    'POST',
    ['unsubscribe'],
    root: 'push',
    body: {'endpoint': endpoint},
  );

  @override
  Future<List<ServerApp>> apps(String workspace) async =>
      appsOf(workspace, await _json('GET', [workspace]));

  @override
  Future<ServerApp?> app(AppRef app) async {
    final json = await _unlessMissing('app', () => _json('GET', _of(app)));
    return json == null ? null : ServerApp.fromJson(app.workspace, json);
  }

  @override
  Future<LogPage?> log(AppRef app, {int? before, int limit = 100}) async {
    final json = await _unlessMissing(
      'log',
      () => _json(
        'GET',
        [..._of(app), 'log'],
        query: {'before': ?before?.toString(), 'limit': '$limit'},
      ),
    );
    return json == null ? null : LogPage.fromJson(json);
  }

  /// What [read] answers, or null when the apps server does not know its route, [kind], which
  /// is then remembered for the connection.
  Future<Object?> _unlessMissing(
    String kind,
    Future<Object?> Function() read,
  ) async {
    final key = '${_companion.current.baseUrl} $kind';
    if (_missing.contains(key)) return null;
    try {
      return await read();
    } on NoRoute {
      _missing.add(key);
      return null;
    }
  }

  @override
  Future<List<AppFile>> files(AppRef app) async =>
      appFilesOf(await _json('GET', [..._of(app), 'files']));

  @override
  Future<String> file(AppRef app, String path) async {
    final response = await _call(
      'GET',
      [..._of(app), 'file'],
      query: {'path': path},
    );
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  @override
  Future<AppState> state(AppRef app, {int? line}) async => AppState.fromJson(
    await _json(
      'GET',
      [..._of(app), 'state'],
      query: {'line': ?line?.toString()},
    ),
  );

  @override
  Future<List<AppCommit>> history(AppRef app) async =>
      commitsOf(await _json('GET', [..._of(app), 'history']));

  @override
  Future<AppDiff> diff(AppRef app, String commit) async => AppDiff.fromJson(
    await _json('GET', [..._of(app), 'diff'], query: {'commit': commit}),
  );

  @override
  Future<int> restore(AppRef app, int line) async {
    final body = await _json(
      'POST',
      [..._of(app), 'restore'],
      body: {'line': line},
    );
    final made = body is Map ? body['line'] : null;
    return made is Map && made['n'] is int ? made['n'] as int : 0;
  }

  @override
  Future<String> revert(AppRef app, String commit) async {
    final body = await _json(
      'POST',
      [..._of(app), 'revert'],
      body: {'commit': commit},
    );
    return body is Map && body['commit'] is String
        ? body['commit'] as String
        : '';
  }

  @override
  Future<void> rename(AppRef app, String title) =>
      _json('POST', [..._of(app), 'rename'], body: {'title': title});

  @override
  Future<void> delete(AppRef app) => _json('DELETE', _of(app));

  @override
  Future<List<SystemEntry>> systemFolder(String path) async => systemEntriesOf(
    await _json('GET', ['tree'], root: 'system', query: {'path': path}),
  );

  @override
  Future<String?> systemFile(String path) async {
    final response = await _call(
      'GET',
      ['file'],
      root: 'system',
      query: {'path': path},
    );
    if (!(response.headers['content-type'] ?? '').startsWith('text/')) {
      return null;
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  @override
  Future<CardPicture> card(Uri url, {CardPicture? last}) async {
    if (!keySafe(url)) throw const ApiException(plainHttpRefused);
    final tag = last?.etag;
    final response = await _companion.fetch(
      () => _companion.client.get(
        url,
        headers: {'Accept': 'image/png', 'If-None-Match': ?tag},
      ),
    );
    if (response.statusCode == 304 && last != null && tag != null) {
      return last;
    }
    if (response.statusCode != 200) {
      throw ApiException(
        'The card could not be read: the server answered ${response.statusCode}.',
        status: response.statusCode,
      );
    }
    return CardPicture(response.bodyBytes, etag: response.headers['etag']);
  }

  static List<String> _of(AppRef app) => [app.workspace, app.name];

  /// The decoded JSON of a [method] to `/<root>/<path>`.
  Future<Object?> _json(
    String method,
    List<String> path, {
    String root = 'apps',
    Map<String, String> query = const {},
    Map<String, Object?>? body,
  }) => _companion.json(method, [root, ...path], query: query, body: body);

  /// A [method] to `/<root>/<path>` with the key.
  Future<http.Response> _call(
    String method,
    List<String> path, {
    String root = 'apps',
    Map<String, String> query = const {},
  }) => _companion.call(method, [root, ...path], query: query);
}
