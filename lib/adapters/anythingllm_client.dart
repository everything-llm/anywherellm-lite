import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/chat.dart';
import '../core/connection.dart';
import '../core/ports.dart';
import '../core/server_models.dart';
import 'anythingllm_stream.dart';

/// [AnythingLlmApi] over the server's HTTP API, with the bearer key on every request.
///
/// Every call but [verify] reads the connection from the holder when it is made. An error message
/// never contains the key.
class HttpAnythingLlmApi implements AnythingLlmApi {
  HttpAnythingLlmApi({
    required this._holder,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.uploadTimeout = const Duration(minutes: 5),
  }) : _client = client ?? http.Client();

  final ConnectionHolder _holder;
  final http.Client _client;
  final Duration timeout;

  /// The server reads an upload in before it answers, which takes a while for a long PDF.
  final Duration uploadTimeout;

  @override
  Future<void> verify(Connection connection) async {
    final body = await _get(connection, '/api/v1/auth');
    if (body is! Map || body['authenticated'] != true) {
      throw const ApiException('The server did not accept the key.');
    }
  }

  @override
  Future<List<Workspace>> workspaces() async => [
    for (final json in jsonObjects(
      _field(await _get(_current, '/api/v1/workspaces'), 'workspaces'),
    ))
      Workspace.fromJson(json),
  ];

  /// The server answers with a list of the workspaces that have the slug: one, or none.
  @override
  Future<Workspace> workspace(String slug) async {
    final found = jsonObjects(
      _field(
        await _get(_current, '/api/v1/workspace/${Uri.encodeComponent(slug)}'),
        'workspace',
      ),
    );
    if (found.isEmpty) {
      throw ApiException('There is no workspace $slug.', status: 404);
    }
    return Workspace.fromJson(found.first);
  }

  @override
  Future<Workspace> createWorkspace(String name) async {
    final body = await _send('POST', '/api/v1/workspace/new', {'name': name});
    final json = _field(body, 'workspace');
    if (json is! Map<String, dynamic>) {
      throw ApiException(_said(body) ?? 'The server did not make $name.');
    }
    return Workspace.fromJson(json);
  }

  @override
  Future<Thread> createThread(String slug) async {
    final body = await _send('POST', '${_workspace(slug)}/thread/new', {
      'name': newChatName,
    });
    final json = _field(body, 'thread');
    if (json is! Map<String, dynamic>) {
      throw ApiException(_said(body) ?? 'The server did not start a chat.');
    }
    return Thread.fromJson(json);
  }

  @override
  Future<void> renameThread(String slug, String thread, String name) =>
      _send('POST', '${_thread(slug, thread)}/update', {'name': name});

  /// The server answers a delete with an empty body.
  @override
  Future<void> deleteThread(String slug, String thread) =>
      _send('DELETE', _thread(slug, thread), null);

  @override
  Future<List<ChatMessage>> history(String slug, String thread) async => [
    for (final json in jsonObjects(
      _field(await _get(_current, '${_thread(slug, thread)}/chats'), 'history'),
    ))
      ChatMessage.fromJson(json),
  ];

  @override
  Stream<ChatEvent> streamChat(
    String slug,
    String thread,
    String message, {
    required ChatMode mode,
  }) async* {
    final connection = _current;
    final request = _request(
      connection,
      'POST',
      '${_thread(slug, thread)}/stream-chat',
      {'message': message, 'mode': mode.name},
    )..headers['Accept'] = 'text/event-stream';
    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(timeout);
    } on Exception catch (error) {
      throw _unreachable(connection, error);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decode(await http.Response.fromStream(response));
    }
    try {
      yield* chatEvents(response.stream);
    } on http.ClientException catch (error) {
      throw ApiException('The answer was cut off: ${error.message}');
    }
  }

  @override
  Future<void> updateEmbeddings(
    String slug, {
    List<String> adds = const [],
    List<String> deletes = const [],
  }) => _send('POST', '${_workspace(slug)}/update-embeddings', {
    'adds': adds,
    'deletes': deletes,
  });

  /// The server answers with the MIME types it reads and their extensions.
  @override
  Future<Set<String>> acceptedExtensions() async {
    final types = _field(
      await _get(_current, '/api/v1/document/accepted-file-types'),
      'types',
    );
    return {
      if (types is Map)
        for (final extensions in types.values)
          if (extensions is List)
            for (final extension in extensions)
              if (extension is String) extension.toLowerCase(),
    };
  }

  @override
  Future<List<DocEntry>> upload(String name, List<int> bytes) async {
    final connection = _current;
    const path = '/api/v1/document/upload';
    final body = await _call(connection, uploadTimeout, () async {
      final request =
          http.MultipartRequest('POST', Uri.parse('${connection.baseUrl}$path'))
            ..headers.addAll(_headers(connection))
            ..files.add(
              http.MultipartFile.fromBytes('file', bytes, filename: name),
            );
      return http.Response.fromStream(await _client.send(request));
    });
    if (body is Map && body['success'] == false) {
      throw ApiException(_said(body) ?? 'The server could not read $name in.');
    }
    return [
      for (final json in jsonObjects(_field(body, 'documents')))
        DocEntry.fromJson(json),
    ];
  }

  /// The connection in use.
  Connection get _current => _holder.current ?? (throw const NotConfigured());

  static String _workspace(String slug) =>
      '/api/v1/workspace/${Uri.encodeComponent(slug)}';

  static String _thread(String slug, String thread) =>
      '${_workspace(slug)}/thread/${Uri.encodeComponent(thread)}';

  Map<String, String> _headers(Connection connection) => {
    'Authorization': 'Bearer ${connection.apiKey}',
    'Accept': 'application/json',
  };

  /// The decoded JSON of a GET to [path] on [connection].
  Future<Object?> _get(Connection connection, String path) => _call(
    connection,
    timeout,
    () => _client.get(
      Uri.parse('${connection.baseUrl}$path'),
      headers: _headers(connection),
    ),
  );

  /// A [method] to [path] on [connection] with the key, and [body] as JSON when given.
  http.Request _request(
    Connection connection,
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) {
    final request = http.Request(
      method,
      Uri.parse('${connection.baseUrl}$path'),
    )..headers.addAll(_headers(connection));
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    return request;
  }

  /// The decoded JSON of a [method] to [path] on the connection in use, with [body] as JSON.
  Future<Object?> _send(
    String method,
    String path,
    Map<String, Object?>? body,
  ) async {
    final connection = _current;
    return _call(
      connection,
      timeout,
      () async => http.Response.fromStream(
        await _client.send(_request(connection, method, path, body)),
      ),
    );
  }

  /// The decoded JSON of the response [send] gets, with failures in plain words.
  Future<Object?> _call(
    Connection connection,
    Duration limit,
    Future<http.Response> Function() send,
  ) async {
    final http.Response response;
    try {
      response = await send().timeout(limit);
    } on Exception catch (error) {
      throw _unreachable(connection, error, limit);
    }
    return _decode(response);
  }

  /// [error], from sending a request, in plain words.
  ApiException _unreachable(
    Connection connection,
    Exception error, [
    Duration? limit,
  ]) => switch (error) {
    TimeoutException() => ApiException(
      'The server did not answer within ${_duration(limit ?? timeout)}.',
    ),
    HandshakeException() => const ApiException(
      'The server\'s certificate could not be verified.',
    ),
    SocketException(:final message) => ApiException(
      'Could not reach ${connection.host}: $message',
    ),
    http.ClientException(:final message) => ApiException(
      'Could not reach the server: $message',
    ),
    _ => ApiException('Could not reach the server: $error'),
  };

  /// The decoded JSON of [response], or null for an empty success, as a delete answers.
  Object? _decode(http.Response response) {
    final status = response.statusCode;
    final body = _json(response);
    if (status == 401 || status == 403) {
      throw ApiException('The server rejected the key.', status: status);
    }
    if (status < 200 || status >= 300) {
      throw ApiException(
        _said(body) ?? 'The server answered HTTP $status.',
        status: status,
      );
    }
    if (body == null && response.bodyBytes.isNotEmpty) {
      throw ApiException(
        'The address did not answer like an AnythingLLM server.',
        status: status,
      );
    }
    return body;
  }

  /// The decoded JSON of [response], or null when it is not JSON.
  Object? _json(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  /// [key] of a JSON object, or null when [body] is not one.
  Object? _field(Object? body, String key) => body is Map ? body[key] : null;

  /// The `error` or `message` the server put in a failed response, when it did.
  String? _said(Object? body) {
    if (body is! Map) return null;
    final said = body['error'] ?? body['message'];
    return said is String && said.trim().isNotEmpty ? said.trim() : null;
  }

  static String _duration(Duration limit) => limit.inSeconds < 120
      ? '${limit.inSeconds} seconds'
      : '${limit.inMinutes} minutes';
}
