import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/chat.dart';
import '../core/connection.dart';
import '../core/ports.dart';
import '../core/server_models.dart';
import '../core/upload.dart';
import 'anythingllm_stream.dart';

/// [AnythingLlmApi] over the server's HTTP API, with the bearer key on every request.
///
/// Every call but [verify] reads the connection from the holder when it is made. An error message
/// never contains the key. Unless [allowHttp], a call to an `http://` address fails before the key
/// is sent.
class HttpAnythingLlmApi implements AnythingLlmApi {
  HttpAnythingLlmApi({
    required this._holder,
    this.allowHttp = true,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.uploadTimeout = const Duration(minutes: 5),
  }) : _client = client ?? http.Client();

  final ConnectionHolder _holder;

  /// Whether the key may go to an `http://` address. False on Android: Dart's HTTP client ignores
  /// Android's cleartext policy, so the client applies it.
  final bool allowHttp;
  final http.Client _client;
  final Duration timeout;

  /// The server reads an upload in before it answers, which takes a while for a long PDF.
  final Duration uploadTimeout;

  @override
  Future<void> verify(Connection connection) async {
    final body = await _get(_secure(connection), '/api/v1/auth');
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
      _field(await _get(_current, _workspace(slug)), 'workspace'),
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
      _send('DELETE', _thread(slug, thread), null, emptyOk: true);

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
    List<Attachment> attachments = const [],
  }) async* {
    final connection = _current;
    final request = _request(
      connection,
      'POST',
      '${_thread(slug, thread)}/stream-chat',
      {
        'message': message,
        'mode': mode.name,
        if (attachments.isNotEmpty)
          'attachments': [for (final a in attachments) attachmentJson(a)],
      },
    )..headers['Accept'] = 'text/event-stream';
    final http.StreamedResponse response;
    try {
      response = await _client
          .send(request)
          .timeout(attachments.isEmpty ? timeout : uploadTimeout);
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
    }, refused: 'The server could not read $name in.');
    return [
      for (final json in jsonObjects(_field(body, 'documents')))
        DocEntry.fromJson(json),
    ];
  }

  @override
  Future<List<DocEntry>> uploadLink(String url) => _readIn(
    '/api/v1/document/upload-link',
    {'link': url},
    refused: 'The server could not read $url.',
  );

  /// The server requires a `title` in the metadata.
  @override
  Future<List<DocEntry>> uploadText(String title, String text) =>
      _readIn('/api/v1/document/raw-text', {
        'textContent': text,
        'metadata': {'title': title},
      }, refused: 'The server could not save $title.');

  /// Posts [body] to [path], which reads something in, and returns the documents it made.
  Future<List<DocEntry>> _readIn(
    String path,
    Map<String, Object?> body, {
    required String refused,
  }) async {
    final connection = _current;
    final answer = await _call(
      connection,
      uploadTimeout,
      () async => http.Response.fromStream(
        await _client.send(_request(connection, 'POST', path, body)),
      ),
      refused: refused,
    );
    return [
      for (final json in jsonObjects(_field(answer, 'documents')))
        DocEntry.fromJson(json),
    ];
  }

  /// The server answers with the workspace it wrote, or a `message` saying why it did not.
  @override
  Future<void> updateWorkspace(String slug, Map<String, Object?> fields) async {
    final body = await _send('POST', '${_workspace(slug)}/update', fields);
    if (_field(body, 'workspace') is! Map) {
      throw ApiException(_said(body) ?? 'The server did not save $slug.');
    }
  }

  @override
  Future<void> pinDocument(String slug, String path, {required bool pinned}) =>
      _send('POST', '${_workspace(slug)}/update-pin', {
        'docPath': path,
        'pinStatus': pinned,
      });

  /// The server answers with its `documents` folder, whose items are the library's folders.
  @override
  Future<List<LibraryFolder>> libraryFolders() async => libraryOf(
    _field(await _get(_current, '/api/v1/documents'), 'localFiles'),
  );

  /// The server finds a document by its file name in any folder.
  @override
  Future<DocBody> document(String path) async {
    final name = docName(path);
    final json = _field(
      await _get(_current, '/api/v1/document/${Uri.encodeComponent(name)}'),
      'document',
    );
    if (json is! Map<String, dynamic>) {
      throw ApiException('There is no document $name.', status: 404);
    }
    return DocBody.fromJson(json);
  }

  @override
  Future<void> createFolder(String name) => _send(
    'POST',
    '/api/v1/document/create-folder',
    {'name': name},
    refused: 'The server did not make the folder $name.',
  );

  @override
  Future<void> moveDocuments(List<(String, String)> moves) =>
      _send('POST', '/api/v1/document/move-files', {
        'files': [
          for (final (from, to) in moves) {'from': from, 'to': to},
        ],
      }, refused: 'The server did not move the documents.');

  @override
  Future<void> removeDocuments(List<String> paths) => _send(
    'DELETE',
    '/api/v1/system/remove-documents',
    {'names': paths},
    refused: 'The server did not delete the documents.',
  );

  @override
  Future<Map<String, Object?>> systemSettings() async {
    final settings = _field(await _get(_current, '/api/v1/system'), 'settings');
    return settings is Map<String, dynamic> ? settings : const {};
  }

  /// The connection in use.
  Connection get _current =>
      _secure(_holder.current ?? (throw const NotConfigured()));

  /// [connection], or an [ApiException] when it is `http://` and [allowHttp] is false.
  Connection _secure(Connection connection) {
    if (!allowHttp && Uri.parse(connection.baseUrl).scheme == 'http') {
      throw const ApiException(
        'Use an https:// address. This device does not send the API key over plain http.',
      );
    }
    return connection;
  }

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
  /// [emptyOk] and [refused] are as for [_decode].
  Future<Object?> _send(
    String method,
    String path,
    Map<String, Object?>? body, {
    bool emptyOk = false,
    String refused = _refused,
  }) async {
    final connection = _current;
    return _call(
      connection,
      timeout,
      () async => http.Response.fromStream(
        await _client.send(_request(connection, method, path, body)),
      ),
      emptyOk: emptyOk,
      refused: refused,
    );
  }

  /// The decoded JSON of the response [send] gets, with failures in plain words.
  Future<Object?> _call(
    Connection connection,
    Duration limit,
    Future<http.Response> Function() send, {
    bool emptyOk = false,
    String refused = _refused,
  }) async {
    final http.Response response;
    try {
      response = await send().timeout(limit);
    } on Exception catch (error) {
      throw _unreachable(connection, error, limit);
    }
    return _decode(response, emptyOk: emptyOk, refused: refused);
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

  static const _refused = 'The server refused the request.';

  /// The decoded JSON of [response], or null for an empty success when [emptyOk], as a delete
  /// answers. An answer with `success: false` fails, even with HTTP 200, with the server's reason
  /// or else [refused].
  Object? _decode(
    http.Response response, {
    bool emptyOk = false,
    String refused = _refused,
  }) {
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
    if (body == null && !(emptyOk && response.bodyBytes.isEmpty)) {
      throw ApiException(
        'The address did not answer like an AnythingLLM server.',
        status: status,
      );
    }
    if (body is Map && body['success'] == false) {
      throw ApiException(_said(body) ?? refused, status: status);
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

/// [attachment] as the server takes it: the file as a base64 data URL. A document's URL carries
/// its own type, or `application/octet-stream`, while [Attachment.mime] tells the server to read
/// it in.
Map<String, String> attachmentJson(Attachment attachment) {
  final type = attachment.isImage
      ? attachment.mime
      : _documentTypes[extensionOf(attachment.name)] ??
            'application/octet-stream';
  return {
    'name': attachment.name,
    'mime': attachment.mime,
    'contentString': 'data:$type;base64,${base64Encode(attachment.bytes)}',
  };
}

const _documentTypes = {
  '.pdf': 'application/pdf',
  '.txt': 'text/plain',
  '.md': 'text/markdown',
  '.csv': 'text/csv',
  '.html': 'text/html',
  '.json': 'application/json',
  '.docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
};
