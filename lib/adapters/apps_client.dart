import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/apps.dart';
import '../core/connection.dart';
import '../core/ports.dart';

/// [AppsApi] over the apps server's client API, on the AnythingLLM server's host at
/// [appsCardsPort], with the connection's developer key on every `/apps/` call.
///
/// Every call reads the connection from the holder when it is made, and goes over https only.
/// An error message never contains the key.
class HttpAppsApi implements AppsApi {
  HttpAppsApi({
    required this._holder,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.healthTimeout = const Duration(seconds: 5),
  }) : _client = client ?? http.Client();

  final ConnectionHolder _holder;
  final http.Client _client;
  final Duration timeout;

  /// How long `/health` may take before the apps server is taken to be absent.
  final Duration healthTimeout;

  /// Whether the apps server answered, by the address of the AnythingLLM server beside it.
  final _found = <String, Future<bool>>{};

  /// The routes an older apps server answered as unknown, by the address of the AnythingLLM
  /// server beside it and the route's kind (`app`, `log`), so they are not asked again until
  /// [available] asks again.
  final _missing = <String>{};

  @override
  Future<bool> available({bool again = false}) {
    final connection = _holder.current;
    if (connection == null || connection.uri.scheme != 'https') {
      return Future.value(false);
    }
    final key = connection.baseUrl;
    if (again) {
      _found.remove(key);
      _missing.removeWhere((missing) => missing.startsWith('$key '));
    }
    return _found[key] ??= _health(connection);
  }

  Future<bool> _health(Connection connection) async {
    try {
      final response = await _client
          .get(
            appsBase(connection.uri).replace(path: '/health'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(healthTimeout);
      if (response.statusCode != 200) return false;
      return isAppsHealth(jsonDecode(utf8.decode(response.bodyBytes)));
    } on Object {
      return false;
    }
  }

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
    final key = '${_current.baseUrl} $kind';
    if (_missing.contains(key)) return null;
    try {
      return await read();
    } on _NoRoute {
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
  Future<CardPicture> card(Uri url, {CardPicture? last}) async {
    if (url.scheme != 'https') {
      throw const ApiException('Cards load over https only.');
    }
    final connection = _current;
    final tag = last?.etag;
    final response = await _fetch(
      connection,
      () => _client.get(
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

  Connection get _current {
    final connection = _holder.current ?? (throw const NotConfigured());
    if (connection.uri.scheme != 'https') {
      throw const ApiException(
        'Use an https:// address. This device does not sign in over plain http.',
      );
    }
    return connection;
  }

  /// The decoded JSON of a [method] to `/apps/<path>`.
  Future<Object?> _json(
    String method,
    List<String> path, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
  }) async {
    final response = await _call(method, path, query: query, body: body);
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const ApiException('The apps server did not answer with JSON.');
    }
  }

  /// A [method] to `/apps/<path>` with the key, failing with the server's words on any status
  /// but a success.
  Future<http.Response> _call(
    String method,
    List<String> path, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
  }) async {
    final connection = _current;
    final url = appsBase(connection.uri).replace(
      pathSegments: ['apps', ...path],
      queryParameters: query.isEmpty ? null : query,
    );
    final request = http.Request(method, url)
      ..headers['Authorization'] = 'Bearer ${connection.apiKey}'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    final response = await _fetch(
      connection,
      () async => http.Response.fromStream(await _client.send(request)),
    );
    final status = response.statusCode;
    if (status >= 200 && status < 300) return response;
    if (status == 401) {
      throw const ApiException(
        'The apps server did not accept the key.',
        status: 401,
      );
    }
    final said = _said(response);
    // The server words every failure of its own; a bare 404 or 405 is a route it lacks.
    if (said == null && (status == 404 || status == 405)) {
      throw _NoRoute(status);
    }
    throw ApiException(
      said ?? 'The apps server answered HTTP $status.',
      status: status,
    );
  }

  /// What [send] gets within [timeout], or an [ApiException] in plain words.
  Future<T> _fetch<T>(Connection connection, Future<T> Function() send) async {
    try {
      return await send().timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        'The apps server did not answer within ${timeout.inSeconds} seconds.',
      );
    } on HandshakeException {
      throw const ApiException(
        'The apps server\'s certificate could not be verified.',
      );
    } on SocketException catch (error) {
      throw ApiException(
        'Could not reach the apps server on ${connection.host}: ${error.message}',
      );
    } on http.ClientException catch (error) {
      throw ApiException('Could not reach the apps server: ${error.message}');
    }
  }

  /// The `error` the apps server put in a failed answer, with its first letter raised.
  static String? _said(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final said = body is Map ? body['error'] : null;
      if (said is! String || said.trim().isEmpty) return null;
      final text = said.trim();
      return '${text[0].toUpperCase()}${text.substring(1)}.'.replaceAll(
        RegExp(r'\.\.$'),
        '.',
      );
    } on FormatException {
      return null;
    }
  }
}

/// A route the apps server does not have, as an older one answers: a 404 or 405 without the
/// `error` it words its own failures with.
class _NoRoute extends ApiException {
  _NoRoute(int status)
    : super('The apps server answered HTTP $status.', status: status);
}
