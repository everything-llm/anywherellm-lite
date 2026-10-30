import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../core/chat.dart';
import '../core/connection.dart';
import '../core/json.dart';
import '../core/ports.dart';
import '../core/server_models.dart';
import '../core/upload.dart';
import '../core/users.dart';
import 'anythingllm_stream.dart';
import 'unreachable.dart';

/// [AnythingLlmApi] over the server's HTTP API, with the bearer key on every request.
///
/// Every call but [verify] reads the connection from the holder when it is made. An error message
/// never contains the key. A call to an `http://` address fails before the key is sent: Dart's
/// HTTP client ignores Android's cleartext policy, so the client applies it.
class HttpAnythingLlmApi implements AnythingLlmApi {
  HttpAnythingLlmApi({
    required this._holder,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.idle = const Duration(minutes: 5),
  }) : assert(client != null || connectTimeout < timeout),
       _client =
           client ?? IOClient(HttpClient()..connectionTimeout = connectTimeout);

  /// How long connecting may take, shorter than [timeout]: a server that cannot be reached fails
  /// as a [SocketException], so a [TimeoutException] means a server that took the request and has
  /// not answered.
  static const connectTimeout = Duration(seconds: 10);

  /// How long a call that sends a file may take: the server reads an upload in before it
  /// answers, which takes a while for a long PDF.
  static const uploadTimeout = Duration(minutes: 5);

  final ConnectionHolder _holder;

  final http.Client _client;
  final Duration timeout;

  /// How long an answer or a reset may send nothing before it is given up. AnythingLLM
  /// sends no pings, and an agent's tool can run a while without a word.
  final Duration idle;

  @override
  Future<void> verify(Connection connection) async {
    final body = await _get('/api/v1/auth', on: connection);
    if (body is! Map || body['authenticated'] != true) {
      throw const ApiException('The server did not accept the key.');
    }
  }

  @override
  Future<List<Workspace>> workspaces() async =>
      _list(await _get('/api/v1/workspaces'), 'workspaces', Workspace.fromJson);

  /// The server answers with a list of the workspaces that have the slug: one, or none.
  @override
  Future<Workspace> workspace(String slug) async {
    final found = jsonObjects(
      _field(await _get(_workspace(slug)), 'workspace'),
    );
    if (found.isEmpty) {
      throw ApiException('There is no workspace $slug.', status: 404);
    }
    return Workspace.fromJson(found.first);
  }

  @override
  Future<Workspace> createWorkspace(String name, {String? prompt}) async {
    final body = await _send('POST', '/api/v1/workspace/new', {
      'name': name,
      'openAiPrompt': ?prompt,
    });
    return Workspace.fromJson(
      _written(body, 'workspace', 'The server did not make $name.'),
    );
  }

  /// The server answers with the workspace it wrote, or a `message` saying why it did not.
  @override
  Future<Workspace> renameWorkspace(String slug, String name) async {
    final body = await _send('POST', '${_workspace(slug)}/update', {
      'name': name,
    });
    return Workspace.fromJson(
      _written(body, 'workspace', 'The server did not rename $slug.'),
    );
  }

  /// The server answers a delete with no JSON. Deleting a workspace leaves its documents in the
  /// library.
  @override
  Future<void> deleteWorkspace(String slug) =>
      _send('DELETE', _workspace(slug), null, emptyOk: true);

  /// The server saves the thread as user [userId] without checking it, on a multi-user server.
  @override
  Future<Thread> createThread(String slug, {int? userId}) async {
    final body = await _send('POST', '${_workspace(slug)}/thread/new', {
      'name': newChatName,
      'userId': ?userId,
    });
    return Thread.fromJson(
      _written(body, 'thread', 'The server did not start a chat.'),
    );
  }

  @override
  Future<void> renameThread(String slug, String thread, String name) =>
      _send('POST', '${_thread(slug, thread)}/update', {'name': name});

  /// The server answers a delete with an empty body.
  @override
  Future<void> deleteThread(String slug, String thread, {Connection? on}) =>
      _send('DELETE', _thread(slug, thread), null, emptyOk: true, on: on);

  /// How many of Main chat's newest exchanges [history] reads, as its `limit`: the server reads
  /// 100 when given none. The spec counts the limit in messages, which would halve it.
  static const mainChatExchanges = 10000;

  /// A thread's history is the whole of it. Main chat's is `workspace/{slug}/chats`, which gives
  /// only the chats in no thread; it is read newest first, so a chat longer than
  /// [mainChatExchanges] still ends at its newest, and put oldest first.
  @override
  Future<List<ChatMessage>> history(String slug, String? thread) async {
    final read = _list(
      await _get(
        thread == null
            ? '${_workspace(slug)}/chats?orderBy=desc&limit=$mainChatExchanges'
            : '${_thread(slug, thread)}/chats',
      ),
      'history',
      ChatMessage.fromJson,
    );
    return thread == null ? _oldestFirst(read) : read;
  }

  /// [history] read newest exchange first, put oldest first, each question still before its
  /// answer. An exchange starts at a question. A history whose exchange ids already rise, as
  /// from a server that took no `orderBy`, is kept as it came.
  static List<ChatMessage> _oldestFirst(List<ChatMessage> history) {
    final exchanges = <List<ChatMessage>>[];
    for (final message in history) {
      if (message.role == Role.user || exchanges.isEmpty) {
        exchanges.add([message]);
      } else {
        exchanges.last.add(message);
      }
    }
    final (first, last) = (
      exchanges.firstOrNull?.first.chatId,
      exchanges.lastOrNull?.first.chatId,
    );
    if (first != null && last != null && first < last) return history;
    return [for (final exchange in exchanges.reversed) ...exchange];
  }

  @override
  Stream<ChatEvent> streamChat(
    String slug,
    String? thread,
    String message, {
    List<Attachment> attachments = const [],
    ChatMode? mode,
    int? userId,
  }) {
    // With no `mode` the server answers in the workspace's own chat mode. It takes `userId` as
    // given, without checking it.
    final body = {
      'message': message,
      'mode': ?mode?.name,
      'userId': ?userId,
      if (attachments.isNotEmpty)
        'attachments': [for (final a in attachments) attachmentJson(a)],
    };
    final limit = attachments.isEmpty ? timeout : uploadTimeout;
    return _events('${_chat(slug, thread)}/stream-chat', body, limit);
  }

  /// A `stream-chat` with `reset` and no message, which clears the history and answers with
  /// one closing chunk.
  @override
  Future<void> resetChat(String slug, String? thread) => _events(
    '${_chat(slug, thread)}/stream-chat',
    {'reset': true},
    timeout,
  ).drain<void>();

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
      await _get('/api/v1/document/accepted-file-types'),
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
    DocMeta meta = const DocMeta(),
  }) async {
    final connection = _current;
    const path = '/api/v1/document/upload';
    final body = await _call(connection, uploadTimeout, () async {
      final request =
          http.MultipartRequest('POST', Uri.parse('${connection.baseUrl}$path'))
            ..headers.addAll(_headers(connection))
            ..files.add(
              http.MultipartFile.fromBytes('file', bytes, filename: name),
            );
      if (!meta.isEmpty) request.fields['metadata'] = jsonEncode(meta.toJson());
      return http.Response.fromStream(await _client.send(request));
    }, refused: 'The server could not read $name in.');
    return _documents(body);
  }

  @override
  Future<List<DocEntry>> uploadLink(
    String url, {
    DocMeta meta = const DocMeta(),
  }) async => _documents(
    await _send(
      'POST',
      '/api/v1/document/upload-link',
      {'link': url, if (!meta.isEmpty) 'metadata': meta.toJson()},
      limit: uploadTimeout,
      refused: 'The server could not read $url.',
    ),
  );

  /// The server requires a `title` in the metadata.
  @override
  Future<List<DocEntry>> uploadText(
    String title,
    String text, {
    DocMeta meta = const DocMeta(),
  }) async => _documents(
    await _send(
      'POST',
      '/api/v1/document/raw-text',
      {
        'textContent': text,
        'metadata': {...meta.toJson(), 'title': title},
      },
      limit: uploadTimeout,
      refused: 'The server could not save $title.',
    ),
  );

  /// The documents an upload, a link or pasted text made, from the server's answer [body].
  List<DocEntry> _documents(Object? body) =>
      _list(body, 'documents', DocEntry.fromJson);

  /// The server answers with the workspace it wrote, or a `message` saying why it did not.
  @override
  Future<void> updateWorkspace(String slug, Map<String, Object?> fields) async {
    final body = await _send('POST', '${_workspace(slug)}/update', fields);
    if (_field(body, 'workspace') is! Map) {
      throw ApiException(saidIn(body) ?? 'The server did not save $slug.');
    }
  }

  @override
  Future<List<SearchHit>> searchDocs(String slug, String query) async => _list(
    await _send('POST', '${_workspace(slug)}/vector-search', {'query': query}),
    'results',
    SearchHit.fromJson,
  );

  @override
  Future<List<int>> generatedFile(String storageName) => _file(
    '/api/v1/document/generated-files/${Uri.encodeComponent(storageName)}',
  );

  /// A bare `GET` of [url], on any port of the server's host as [loadableImage] allows, read
  /// whole, at most [maxImageBytes]. Any other address is refused unread ([offServerImage]), and
  /// a redirect is not followed, since it could lead to one.
  @override
  Future<Uint8List> answerImage(Uri url) async {
    final connection = _current;
    if (!keySafe(url)) throw const ApiException(plainHttpRefused);
    if (!loadableImage(url, connection.uri)) {
      throw const ApiException(offServerImage);
    }
    final response = await _fetch(
      connection,
      timeout,
      () => _client.send(http.Request('GET', url)..followRedirects = false),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      unawaited(response.stream.listen(null).cancel());
      throw ApiException(
        'The image could not be read: the server answered ${response.statusCode}.',
      );
    }
    final bytes = BytesBuilder(copy: false);
    try {
      await for (final chunk in response.stream.timeout(timeout)) {
        bytes.add(chunk);
        if (bytes.length > maxImageBytes) {
          throw const ApiException('The image is too large to show.');
        }
      }
    } on TimeoutException {
      throw ApiException(
        'The server did not answer within ${durationText(timeout)}.',
      );
    } on http.ClientException catch (error) {
      throw ApiException('The image was cut off: ${error.message}');
    }
    return bytes.takeBytes();
  }

  /// The bytes of the file the server answers [path] with, which is not always JSON; a failure
  /// is decoded as any other. An HTML page is the web UI's own, as from an address the server
  /// does not have, unless the server hands it over as an attachment, as an HTML file an agent
  /// made.
  Future<List<int>> _file(String path) async {
    final connection = _current;
    final request = _request(connection, 'GET', path)
      ..headers['Accept'] = '*/*';
    final response = await _fetch(
      connection,
      uploadTimeout,
      () async => http.Response.fromStream(await _client.send(request)),
    );
    final type = response.headers['content-type'] ?? '';
    final attached = (response.headers['content-disposition'] ?? '')
        .trimLeft()
        .toLowerCase()
        .startsWith('attachment');
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok || (type.startsWith('text/html') && !attached)) {
      _decode(response);
      throw const ApiException(_refused);
    }
    return response.bodyBytes;
  }

  @override
  Future<Map<String, Object?>> systemSettings() async {
    final settings = _field(await _get('/api/v1/system'), 'settings');
    return settings is Map<String, dynamic> ? settings : const {};
  }

  /// The server answers the settings it wrote in `newValues` and the first refusal in `error`;
  /// it drops a key it does not know without a word, so each key sent must come back.
  @override
  Future<void> updateSystem(Map<String, String> changes) async {
    final answer = await _send(
      'POST',
      '/api/v1/system/update-env',
      changes,
      refused: 'The server did not change its settings.',
    );
    _failOnError(answer);
    final written = _field(answer, 'newValues');
    final missing = [
      for (final key in changes.keys)
        if (written is! Map || !written.containsKey(key)) key,
    ];
    if (missing.isNotEmpty) {
      throw ApiException('The server did not write ${missing.join(', ')}.');
    }
  }

  @override
  Future<int> vectorCount() async => switch (_field(
    await _get('/api/v1/system/vector-count'),
    'vectorCount',
  )) {
    final num count => count.toInt(),
    _ => throw const ApiException(_refused),
  };

  /// A single-user server answers too, with `isMultiUser` false.
  @override
  Future<bool> multiUser() async =>
      _field(await _get('/api/v1/admin/is-multi-user-mode'), 'isMultiUser') ==
      true;

  /// A single-user server answers HTTP 401, which reads as a rejected key.
  @override
  Future<List<ServerUser>> users() async => [
    for (final json in jsonObjects(
      _field(await _get('/api/v1/users'), 'users'),
    ))
      ?ServerUser.fromJson(json),
  ];

  /// The server's own schema lists each as `userId` and `role`; one that carries `username`
  /// instead of an id is matched by it.
  @override
  Future<List<WorkspaceMember>> workspaceUsers(int workspaceId) async => [
    for (final json in jsonObjects(
      _field(
        await _get('/api/v1/admin/workspaces/$workspaceId/users'),
        'users',
      ),
    ))
      ?WorkspaceMember.fromJson(json),
  ];

  /// The server answers the CSV itself, as `text/csv`, with every user's chats.
  @override
  Future<List<int>> exportChats() =>
      _file('/api/v1/system/export-chats?type=csv');

  /// The connection in use.
  Connection get _current =>
      _secure(_holder.current ?? (throw const NotConfigured()));

  /// [connection], or an [ApiException] when it is `http://`.
  Connection _secure(Connection connection) {
    if (!keySafe(connection.uri)) throw const ApiException(plainHttpRefused);
    return connection;
  }

  static String _workspace(String slug) =>
      '/api/v1/workspace/${Uri.encodeComponent(slug)}';

  static String _thread(String slug, String thread) =>
      '${_workspace(slug)}/thread/${Uri.encodeComponent(thread)}';

  /// Where chat [thread] of workspace [slug] is asked: its thread, or for Main chat, a null
  /// [thread], the workspace itself. No `sessionId` is sent, so what Main chat is asked shows in
  /// the workspace's chat on AnythingLLM's web page too.
  static String _chat(String slug, String? thread) =>
      thread == null ? _workspace(slug) : _thread(slug, thread);

  Map<String, String> _headers(Connection connection) => {
    'Authorization': 'Bearer ${connection.apiKey}',
    'Accept': 'application/json',
  };

  /// The decoded JSON of a GET to [path] on the connection in use, or on [on].
  Future<Object?> _get(String path, {Connection? on}) =>
      _send('GET', path, null, on: on);

  /// The events of a POST of [body] to [path], whose answer streams server-sent events. A
  /// failed status, or a server that cannot be reached, is a [NotSent] with the server's words.
  /// A stream that drops or falls silent, once it has begun or after the request went out, is a
  /// [CutOff], since the server may have the question and still finish it. A cancel lets go of
  /// the response at once, even before the first event, as the `async*` readers of [chatEvents]
  /// would not until their next `yield`: the server stops answering when the connection closes.
  Stream<ChatEvent> _events(
    String path,
    Map<String, Object?> body,
    Duration limit,
  ) {
    late final StreamController<ChatEvent> out;
    StreamSubscription<ChatEvent>? reading;
    // The response's bytes, read here rather than by [chatEvents], so a cancel can close it.
    StreamSubscription<List<int>>? response;
    final bytes = StreamController<List<int>>();
    var cancelled = false;
    // Whether the server took the question: its answer's headers came.
    var began = false;
    Future<void> fail(Object error) async {
      if (cancelled) return;
      out.addError(switch (error) {
        http.ClientException(:final message) when began => CutOff(
          'The connection dropped: $message',
        ),
        TimeoutException() when began => const CutOff(
          'The server sent nothing for too long, so the connection was let go.',
        ),
        http.ClientException(:final message) => ApiException(
          'The answer was cut off: $message',
        ),
        NotConfigured() || CutOff() => error,
        // Otherwise, before the headers came the server never took the question.
        ApiException(:final message, :final status) when !began => NotSent(
          message,
          status: status,
        ),
        _ => error,
      });
      await out.close();
    }

    Future<void> start() async {
      try {
        final connection = _current;
        final request = _request(connection, 'POST', path, body)
          ..headers['Accept'] = 'text/event-stream';
        final http.StreamedResponse answer;
        try {
          answer = await _client.send(request).timeout(limit);
        } on Exception catch (error) {
          throw switch (error) {
            // Connecting takes less than [limit], so the request went out.
            TimeoutException() => CutOff(
              'The server took the question but sent nothing within ${durationText(limit)}. It may '
              'still be answering.',
            ),
            // An [HttpException]: the server closed the connection after the request went out.
            http.ClientException(:final message)
                when error is! SocketException =>
              CutOff('The connection closed before the answer began: $message'),
            _ => _unreachable(connection, error, limit),
          };
        }
        if (cancelled) {
          unawaited(answer.stream.listen(null).cancel());
          return;
        }
        if (answer.statusCode < 200 || answer.statusCode >= 300) {
          _decode(await http.Response.fromStream(answer));
        }
        began = true;
        response = answer.stream
            .timeout(idle)
            .listen(
              bytes.add,
              onError: bytes.addError,
              onDone: bytes.close,
              cancelOnError: true,
            );
        reading = chatEvents(bytes.stream).listen(
          out.add,
          onError: (Object error) {
            unawaited(response?.cancel());
            unawaited(bytes.close());
            unawaited(fail(error));
          },
          onDone: out.close,
          cancelOnError: true,
        );
      } on Object catch (error) {
        await fail(error);
      }
    }

    out = StreamController(
      onListen: () => unawaited(start()),
      onCancel: () {
        cancelled = true;
        unawaited(response?.cancel());
        // Ends the readers' `await for`, so their cancel completes now.
        unawaited(bytes.close());
        return reading?.cancel();
      },
    );
    return out.stream;
  }

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
    Duration? limit,
    bool emptyOk = false,
    String refused = _refused,
    Connection? on,
  }) async {
    final connection = on == null ? _current : _secure(on);
    return _call(
      connection,
      limit ?? timeout,
      () async => http.Response.fromStream(
        await _client.send(_request(connection, method, path, body)),
      ),
      emptyOk: emptyOk,
      refused: refused,
    );
  }

  /// The decoded JSON of the response [send] gets, with failures in plain words. [emptyOk] and
  /// [refused] are as for [_decode].
  Future<Object?> _call(
    Connection connection,
    Duration limit,
    Future<http.Response> Function() send, {
    bool emptyOk = false,
    String refused = _refused,
  }) async => _decode(
    await _fetch(connection, limit, send),
    emptyOk: emptyOk,
    refused: refused,
  );

  /// The response [send] gets within [limit], or an [ApiException] in plain words when the
  /// server cannot be reached.
  Future<T> _fetch<T>(
    Connection connection,
    Duration limit,
    Future<T> Function() send,
  ) async {
    try {
      return await send().timeout(limit);
    } on Exception catch (error) {
      throw _unreachable(connection, error, limit);
    }
  }

  /// [error], from sending a request to [connection] that may take [limit], in plain words.
  static ApiException _unreachable(
    Connection connection,
    Exception error,
    Duration limit,
  ) => unreachable(
    error,
    name: 'The server',
    where: connection.host,
    limit: limit,
  );

  static const _refused = 'The server refused the request.';

  /// The decoded JSON of [response], or null for a success that is empty or the bare status
  /// text `OK` when [emptyOk], as a delete answers. An answer with `success: false` fails, even with HTTP 200, with the server's reason
  /// or else [refused]. A 401 or 403 fails as a rejected key, whatever the server said.
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
        saidIn(body) ?? 'The server answered HTTP $status.',
        status: status,
      );
    }
    if (body == null &&
        !(emptyOk &&
            (response.bodyBytes.isEmpty || response.body.trim() == 'OK'))) {
      throw ApiException(
        'The address did not answer like an AnythingLLM server.',
        status: status,
      );
    }
    if (body is Map && body['success'] == false) {
      throw ApiException(saidIn(body) ?? refused, status: status);
    }
    return body;
  }

  /// The decoded JSON of [response], or null when it is not JSON.
  Object? _json(http.Response response) {
    try {
      return jsonOrNull(utf8.decode(response.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  /// [key] of a JSON object, or null when [body] is not one.
  Object? _field(Object? body, String key) => body is Map ? body[key] : null;

  /// The objects under [key] in the JSON [body], each read by [from].
  List<T> _list<T>(
    Object? body,
    String key,
    T Function(Map<String, dynamic>) from,
  ) => [for (final json in jsonObjects(_field(body, key))) from(json)];

  /// The object under [key] in the JSON [body] that wrote it, or an [ApiException] with the
  /// server's reason, or else [failed].
  Map<String, dynamic> _written(Object? body, String key, String failed) =>
      switch (_field(body, key)) {
        final Map<String, dynamic> json => json,
        _ => throw ApiException(saidIn(body) ?? failed),
      };

  /// Fails with the `error` the server put in an answer that succeeded, when it did.
  void _failOnError(Object? body) {
    if (_field(body, 'error') case final String error
        when error.trim().isNotEmpty) {
      throw ApiException(error.trim());
    }
  }
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

/// The most bytes one image in an answer may take.
const maxImageBytes = 16 * 1024 * 1024;

/// Why an image in an answer on any host but the server's is not read.
const offServerImage =
    'The image is not on your AnythingLLM server, so it was not read.';

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
