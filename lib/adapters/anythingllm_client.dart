import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/connection.dart';
import '../core/ports.dart';
import '../core/server_models.dart';

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
  Future<List<DocFolder>> documents() async {
    final root = _field(
      await _get(_current, '/api/v1/documents'),
      'localFiles',
    );
    return [
      for (final json in jsonObjects(root is Map ? root['items'] : null))
        DocFolder.fromJson(json),
    ];
  }

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
  Future<List<DocEntry>> upload(
    String name,
    List<int> bytes, {
    String? folder,
  }) async {
    final connection = _current;
    final path = folder == null
        ? '/api/v1/document/upload'
        : '/api/v1/document/upload/${Uri.encodeComponent(folder)}';
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

  /// The decoded JSON of the response [send] gets, with failures in plain words.
  Future<Object?> _call(
    Connection connection,
    Duration limit,
    Future<http.Response> Function() send,
  ) async {
    final http.Response response;
    try {
      response = await send().timeout(limit);
    } on TimeoutException {
      throw ApiException(
        'The server did not answer within ${_duration(limit)}.',
      );
    } on HandshakeException {
      throw const ApiException(
        'The server\'s certificate could not be verified.',
      );
    } on SocketException catch (error) {
      throw ApiException(
        'Could not reach ${connection.host}: ${error.message}',
      );
    } on http.ClientException catch (error) {
      throw ApiException('Could not reach the server: ${error.message}');
    }
    return _decode(response);
  }

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
    if (body == null) {
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
