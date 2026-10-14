import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/companion.dart';
import '../core/connection.dart';
import '../core/ports.dart';

/// The calls every [Companion] takes, over the connection [holder] has when each is made: its
/// `/health`, asked without the key and remembered by the AnythingLLM server's address, and
/// JSON calls with the developer key, over https only. An error message names the companion
/// and never contains the key.
class CompanionClient {
  CompanionClient(
    this.companion, {
    required this._holder,
    required this.client,
    required this.timeout,
    required this.healthTimeout,
  });

  final Companion companion;
  final ConnectionHolder _holder;

  /// What every call goes through.
  final http.Client client;
  final Duration timeout;

  /// How long `/health` may take before the companion is taken to be absent.
  final Duration healthTimeout;

  /// Each `/health` answer, null when the companion is not there, by the address of the
  /// AnythingLLM server beside it.
  final _found = <String, Future<Object?>>{};

  /// Where the companion runs beside the server in use: where it was said to
  /// ([ConnectionHolder.companions]), or else [Companion.base]'s guess. Null with no server.
  Uri? get address => _holder.addressOf(companion);

  /// The companion's `/health` at [address], or null when it is not there, or the key could not
  /// go there ([keySafe]). Remembered by the address; [again] asks afresh. Never throws.
  Future<Object?> health({bool again = false}) {
    final at = address;
    if (at == null || !keySafe(at)) return Future.value();
    final key = '$at';
    if (again) _found.remove(key);
    return _found[key] ??= _health(at);
  }

  Future<Object?> _health(Uri at) async {
    try {
      final response = await client
          .get(
            under(at, const ['health']),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(healthTimeout);
      if (response.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      return companion.isHealth(json) ? json : null;
    } on Object {
      return null;
    }
  }

  /// The connection in use, whose key may go to [address] ([keySafe]).
  Connection get current {
    final connection = _holder.current ?? (throw const NotConfigured());
    if (!keySafe(address!)) throw const ApiException(plainHttpRefused);
    return connection;
  }

  /// The decoded JSON of a [method] to [path] with the key.
  Future<Object?> json(
    String method,
    List<String> path, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
    Map<String, String> headers = const {},
  }) async {
    final response = await call(
      method,
      path,
      query: query,
      body: body,
      headers: headers,
    );
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException('${companion.name} did not answer with JSON.');
    }
  }

  /// A [method] to [path] with the key, failing with the companion's words on any status but
  /// a success, and with [NoRoute] for a bare 404 or 405.
  Future<http.Response> call(
    String method,
    List<String> path, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
    Map<String, String> headers = const {},
  }) async {
    final connection = current;
    final url = under(address!, path, query);
    final request = http.Request(method, url)
      ..headers.addAll(headers)
      ..headers['Authorization'] = 'Bearer ${connection.apiKey}'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    final response = await fetch(
      () async => http.Response.fromStream(await client.send(request)),
    );
    final status = response.statusCode;
    if (status >= 200 && status < 300) return response;
    if (status == 401) {
      throw ApiException(
        '${companion.name} did not accept the key.',
        status: 401,
      );
    }
    final said = _said(response);
    // A companion words every failure of its own; a bare 404 or 405 is a route it lacks.
    if (said == null && (status == 404 || status == 405)) {
      throw NoRoute(companion, status);
    }
    throw ApiException(
      said ?? '${companion.name} answered HTTP $status.',
      status: status,
    );
  }

  /// What [send] gets within [timeout], or an [ApiException] in plain words.
  Future<T> fetch<T>(Future<T> Function() send) async {
    final name = companion.name;
    try {
      return await send().timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        '$name did not answer within ${timeout.inSeconds} seconds.',
      );
    } on HandshakeException {
      throw ApiException('$name\'s certificate could not be verified.');
    } on SocketException catch (error) {
      throw ApiException(
        'Could not reach ${_lower(name)} on ${address?.host}: ${error.message}',
      );
    } on http.ClientException catch (error) {
      throw ApiException('Could not reach ${_lower(name)}: ${error.message}');
    }
  }

  static String _lower(String name) =>
      name.startsWith('The ') ? 'the ${name.substring(4)}' : name;

  /// The `error` the companion put in a failed answer, with its first letter raised.
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

/// A route the companion does not have, as an older one answers: a 404 or 405 without the
/// `error` it words its own failures with.
class NoRoute extends ApiException {
  NoRoute(Companion companion, int status)
    : super('${companion.name} answered HTTP $status.', status: status);
}
