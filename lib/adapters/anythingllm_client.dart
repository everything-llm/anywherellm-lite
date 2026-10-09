import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/chat.dart';
import '../core/chat_log.dart';
import '../core/commands.dart';
import '../core/connection.dart';
import '../core/embeds.dart';
import '../core/ports.dart';
import '../core/schedule.dart';
import '../core/server_models.dart';
import '../core/upload.dart';
import 'anythingllm_stream.dart';
import 'image_frames.dart';

/// [AnythingLlmApi] over the server's HTTP API, with the bearer key on every request.
///
/// Every call but [verify] reads the connection from the holder when it is made. An error message
/// never contains the key. Unless [allowHttp], a call to an `http://` address fails before the key
/// is sent.
///
/// The everythingllm relay may sit beside AnythingLLM at [relayPath] on the same address and take
/// the same key: it keeps an answer going after the app lets go of it, as a run. A server has the
/// relay when its `GET /everythingllm/health` answers the relay's JSON, asked once per connection.
/// With the relay, [streamChat] starts a run and follows its events, rejoining after the last one
/// it saw when the connection drops.
class HttpAnythingLlmApi implements AnythingLlmApi {
  HttpAnythingLlmApi({
    required this._holder,
    this.allowHttp = true,
    this.browserOrigin,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.uploadTimeout = const Duration(minutes: 5),
    this.quiet = const Duration(seconds: 45),
    this.idle = const Duration(minutes: 5),
    this.rejoinDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
    ],
  }) : _client = client ?? http.Client();

  final ConnectionHolder _holder;

  /// Whether the key may go to an `http://` address. False on Android: Dart's HTTP client ignores
  /// Android's cleartext policy, so the client applies it.
  final bool allowHttp;

  /// The page's origin when the app runs in a browser, where every request is cross-origin and a
  /// server that does not allow it fails like one out of reach; null elsewhere.
  final String? browserOrigin;
  final http.Client _client;
  final Duration timeout;

  /// The server reads an upload in before it answers, which takes a while for a long PDF.
  final Duration uploadTimeout;

  /// How long a relay's run may send nothing before its connection counts as dropped. The relay
  /// pings every 15 s.
  final Duration quiet;

  /// How long a direct answer or a reset may send nothing before it is given up. AnythingLLM
  /// sends no pings, and an agent's tool can run a while without a word.
  final Duration idle;

  /// The waits before each try at rejoining a run whose connection dropped. A run fails once
  /// they are used up without an event coming in between.
  final List<Duration> rejoinDelays;

  /// Whether each connection asked so far is a relay.
  final _relays = <Connection, bool>{};

  /// The run [streamChat] is following in each chat, by workspace and thread: its id once the
  /// relay answers the start, or null when it did not start it.
  final _runs = <(String, String), (Connection, Future<String?>)>{};

  final _random = Random.secure();

  /// The web UI's login token for each connection signed in so far, kept only while the app
  /// runs. The password is what is saved; a token lapses after 30 days or a new password.
  final _tokens = <Connection, String>{};

  /// Where the relay sits on AnythingLLM's address.
  static const relayPath = '/everythingllm';

  @override
  Future<void> verify(Connection connection) async {
    final body = await _get(_secure(connection), '/api/v1/auth');
    if (body is! Map || body['authenticated'] != true) {
      throw const ApiException('The server did not accept the key.');
    }
  }

  /// `GET /api/setup-complete` answers without a key or a login, as the web UI asks it before
  /// it shows its sign-in.
  @override
  Future<ServerAuth> serverAuth(Connection connection) async {
    final secure = _secure(connection);
    final results = _field(
      await _call(
        secure,
        timeout,
        () => _client.get(
          Uri.parse('${secure.baseUrl}/api/setup-complete'),
          headers: {'Accept': 'application/json'},
        ),
      ),
      'results',
    );
    if (results is! Map) {
      throw const ApiException(
        'The address did not answer like an AnythingLLM server.',
      );
    }
    if (results['MultiUserMode'] == true) return ServerAuth.multiUser;
    return results['RequiresAuth'] == true
        ? ServerAuth.password
        : ServerAuth.none;
  }

  @override
  Future<void> signIn(Connection connection) async {
    final secure = _secure(connection);
    _tokens.remove(secure);
    await _token(secure);
  }

  /// The name of the developer key [issueKey] reuses or makes, as the web UI lists it.
  static const keyName = 'AnywhereLLM';

  /// Lists the keys with `GET /api/system/api-keys` and makes one with
  /// `POST /api/system/generate-api-key` only when none is named [keyName], so every device and
  /// every sign-in shares one key.
  @override
  Future<String> issueKey(String baseUrl, {String? password}) async {
    final server = _secure(
      Connection(baseUrl: baseUrl, apiKey: '').withPassword(password),
    );
    final listed = await _session('GET', '/api/system/api-keys', on: server);
    for (final key in jsonObjects(_field(listed, 'apiKeys'))) {
      if (_secret(key) case final secret? when key['name'] == keyName) {
        return secret;
      }
    }
    final made = await _session(
      'POST',
      '/api/system/generate-api-key',
      body: {'name': keyName},
      on: server,
    );
    final key = _field(made, 'apiKey');
    return (key is Map ? _secret(key) : null) ??
        (throw ApiException(_said(made) ?? 'The server did not make a key.'));
  }

  /// The secret of a developer key the server listed, or null when it has none.
  static String? _secret(Map<dynamic, dynamic> key) => switch (key['secret']) {
    final String secret when secret.isNotEmpty => secret,
    _ => null,
  };

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

  /// The server answers with the workspace it wrote, or a `message` saying why it did not.
  @override
  Future<Workspace> renameWorkspace(String slug, String name) async {
    final body = await _send('POST', '${_workspace(slug)}/update', {
      'name': name,
    });
    final json = _field(body, 'workspace');
    if (json is! Map<String, dynamic>) {
      throw ApiException(_said(body) ?? 'The server did not rename $slug.');
    }
    return Workspace.fromJson(json);
  }

  /// The server answers a delete with no JSON. Deleting a workspace leaves its documents in the
  /// library.
  @override
  Future<void> deleteWorkspace(String slug) =>
      _send('DELETE', _workspace(slug), null, emptyOk: true);

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
  Future<void> deleteThread(String slug, String thread, {Connection? on}) =>
      _send('DELETE', _thread(slug, thread), null, emptyOk: true, on: on);

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
    List<Attachment> attachments = const [],
  }) async* {
    final connection = _current;
    // No `mode`: the server then answers in the workspace's own chat mode.
    final body = {
      'message': message,
      if (attachments.isNotEmpty)
        'attachments': [for (final a in attachments) attachmentJson(a)],
    };
    final limit = attachments.isEmpty ? timeout : uploadTimeout;
    if (await _isRelay(connection)) {
      yield* _run(connection, slug, thread, body, limit);
    } else {
      yield* _events('${_thread(slug, thread)}/stream-chat', body, limit);
    }
  }

  /// Cancels the chat's run on the relay, once the relay has said which run it is. The run is
  /// forgotten before the call is sent, so the subscription can be cancelled at once.
  @override
  Future<void> stopChat(String slug, String thread) async {
    final run = _runs.remove((slug, thread));
    if (run == null) return;
    final (connection, started) = run;
    final id = await started;
    if (id == null) return;
    await _call(
      connection,
      timeout,
      () async => http.Response.fromStream(
        await _client.send(
          _request(
            connection,
            'POST',
            '$relayPath/v1/runs/${Uri.encodeComponent(id)}/cancel',
          ),
        ),
      ),
    );
  }

  /// The running run of the chat on the relay, which `GET /everythingllm/v1/runs?status=running`
  /// lists, followed from its first event. The list is read as JSON holding runs, or an object
  /// with them under `runs`; each names its `id`, `workspace` and `thread`, and may carry the
  /// question that started it, as `message` or `question`, or in its `body`. A run whose body is a
  /// `reset` clears the chat and is no answer. A route or an answer that is not there, or no
  /// server set up, reads as no run: opening a chat never fails for this.
  @override
  Future<RejoinedAnswer?> rejoinChat(String slug, String thread) async {
    try {
      final connection = _current;
      if (!await _isRelay(connection)) return null;
      for (final run in await _listRuns(connection, 'running')) {
        final id = run['id'];
        final status = run['status'];
        if (id is! String ||
            run['workspace'] != slug ||
            run['thread'] != thread ||
            (status is String && status != 'running')) {
          continue;
        }
        final known = Future<String>.value(id);
        return (
          question: _questionOf(run),
          events: _letGo(
            (gone) =>
                _followRun(connection, (slug, thread), known, known, gone),
          ),
        );
      }
    } on ApiException {
      return null;
    }
    return null;
  }

  /// The answers the relay ran to their end, from `GET /everythingllm/v1/runs?status=done`. A
  /// server with no relay, or one that cannot be asked, has none.
  @override
  Future<List<RelayRun>> finishedRuns() async {
    try {
      final connection = _current;
      if (!await _isRelay(connection)) return const [];
      return [
        for (final run in await _listRuns(connection, 'done'))
          ?RelayRun.fromJson(run),
      ];
    } on ApiException {
      return const [];
    }
  }

  @override
  Future<List<RelayRun>> relayRuns() async {
    final connection = _current;
    if (!await _isRelay(connection)) {
      throw const ApiException(
        'This server has no everythingllm relay, so it keeps no list of answers.',
      );
    }
    return [
      for (final run in await _listRuns(connection, null))
        // A reset clears a chat and is no answer; the relay names it `/reset`.
        if (run['question'] != '/reset') ?RelayRun.fromJson(run),
    ];
  }

  @override
  Future<void> cancelRun(String id) async {
    final connection = _current;
    await _call(
      connection,
      timeout,
      () async => http.Response.fromStream(
        await _client.send(
          _request(
            connection,
            'POST',
            '$relayPath/v1/runs/${Uri.encodeComponent(id)}/cancel',
          ),
        ),
      ),
    );
  }

  /// The relay's runs of [status], or every kept run when it is null, read as JSON holding runs
  /// or an object with them under `runs`, less those whose body is a `reset`, which clears a chat
  /// and is no answer.
  Future<List<Map<String, dynamic>>> _listRuns(
    Connection connection,
    String? status,
  ) async {
    final listed = await _get(
      connection,
      status == null
          ? '$relayPath/v1/runs'
          : '$relayPath/v1/runs?status=$status',
    );
    return [
      for (final run in jsonObjects(listed is Map ? listed['runs'] : listed))
        if (run['body'] case final Map body when body['reset'] == true)
          ...const <Map<String, dynamic>>[]
        else
          run,
    ];
  }

  /// The question a listed [run] was started with, or null when it does not say.
  String? _questionOf(Map<String, dynamic> run) {
    final body = run['body'];
    for (final said in [
      run['message'],
      run['question'],
      if (body is Map) body['message'],
    ]) {
      if (said is String && said.trim().isNotEmpty) return said.trim();
    }
    return null;
  }

  /// Follows run [id] as [chat]'s run until it ends or [gone] completes. [started] is [id], or
  /// null when the run did not start; [stopChat] reaches the run through it while it is followed.
  Stream<ChatEvent> _followRun(
    Connection connection,
    (String, String) chat,
    Future<String?> started,
    Future<String> id,
    Future<void> gone,
  ) async* {
    _runs[chat] = (connection, started);
    try {
      yield* chatEventsOf(_runChunks(connection, await id, gone));
    } finally {
      if (identical(_runs[chat]?.$2, started)) _runs.remove(chat);
    }
  }

  /// Whether the server at [connection] has the relay: its `GET /everythingllm/health` answers
  /// JSON naming the `everythingllm` service with `runs` among its features. The route is open, so
  /// the key is not sent. AnythingLLM answers a path it does not know with its web page and a 200,
  /// so the body decides. A 5xx is not remembered, so a relay failing for a moment is asked again
  /// on the next message. In a browser a failed request is remembered as no relay, so answers go
  /// to AnythingLLM itself: a relay that does not allow requests from [browserOrigin] fails so on
  /// every ask.
  Future<bool> _isRelay(Connection connection) async {
    final server = connection.withPassword(null);
    if (_relays[server] case final known?) return known;
    final http.Response response;
    try {
      response = await _fetch(
        connection,
        timeout,
        () => _client.get(Uri.parse('${connection.baseUrl}$relayPath/health')),
      );
    } on ApiException {
      if (browserOrigin == null) rethrow;
      return _relays[server] = false;
    }
    if (response.statusCode >= 500) return false;
    final health = response.statusCode == 200 ? _json(response) : null;
    return _relays[server] =
        health is Map &&
        health['service'] == 'everythingllm' &&
        health['features'] is List &&
        (health['features'] as List).contains('runs');
  }

  /// The answer to [body] as a run on the relay at [connection].
  Stream<ChatEvent> _run(
    Connection connection,
    String slug,
    String thread,
    Map<String, Object?> body,
    Duration limit,
  ) => _letGo((gone) => _startRun(connection, slug, thread, body, limit, gone));

  /// The events [start] makes, until [gone] completes. Cancelling the stream completes it, which
  /// closes the connection that follows the run at once, as an `async*` body waiting for the next
  /// event would not; the run itself goes on.
  Stream<ChatEvent> _letGo(
    Stream<ChatEvent> Function(Future<void> gone) start,
  ) {
    final gone = Completer<void>();
    StreamSubscription<ChatEvent>? answer;
    late final StreamController<ChatEvent> out;
    out = StreamController<ChatEvent>(
      onListen: () =>
          answer = start(gone.future)
              .listen(out.add, onError: out.addError, onDone: out.close),
      onPause: () => answer?.pause(),
      onResume: () => answer?.resume(),
      onCancel: () {
        if (!gone.isCompleted) gone.complete();
        return answer?.cancel();
      },
    );
    return out.stream;
  }

  /// Starts the run of [body] and follows it until it ends or [gone] completes. The chat's run
  /// is known before the relay answers, so a stop sent meanwhile cancels it once it has an id.
  /// A chat that already has a run going fails with [AlreadyAnswering].
  Stream<ChatEvent> _startRun(
    Connection connection,
    String slug,
    String thread,
    Map<String, Object?> body,
    Duration limit,
    Future<void> gone,
  ) {
    final id = _beginRun(connection, slug, thread, body, limit);
    final started = id.then<String?>(
      (id) => id,
      onError: (Object error) {
        // A relay that is gone, or whose route is, is asked about again on the next message.
        if (error is ApiException &&
            (error.status == 404 || (error.status ?? 0) >= 500)) {
          _relays.remove(connection.withPassword(null));
        }
        return null;
      },
    );
    return _followRun(connection, (slug, thread), started, id, gone);
  }

  /// Asks the relay to run [body], and gives the run's id. The relay answers a chat that already
  /// has a run going with 409 and says so, which fails with [AlreadyAnswering].
  Future<String> _beginRun(
    Connection connection,
    String slug,
    String thread,
    Map<String, Object?> body,
    Duration limit,
  ) async {
    final Object? run;
    try {
      run = await _call(
        connection,
        limit,
        () async => http.Response.fromStream(
          await _client.send(
            _request(connection, 'POST', '$relayPath/v1/runs', {
              'workspace': slug,
              'thread': thread,
              'clientId': _clientId(),
              'body': body,
            }),
          ),
        ),
        refused: 'The relay did not start the answer.',
      );
    } on ApiException catch (error) {
      if (error.status == 409) throw AlreadyAnswering(error.message);
      rethrow;
    }
    final id = _field(run, 'id');
    if (id is! String) {
      throw const ApiException('The relay did not start the answer.');
    }
    return id;
  }

  /// The `stream-chat` chunks of run [id], as the relay hands them back, until the run ends or
  /// [gone] completes. A connection that drops, or stays [quiet] too long, is opened again after
  /// the last event seen, after each of [rejoinDelays] in turn; an event coming in starts them
  /// over. So is one the relay answers with a 5xx.
  Stream<Map<String, dynamic>> _runChunks(
    Connection connection,
    String id,
    Future<void> gone,
  ) async* {
    var left = false;
    unawaited(gone.then((_) => left = true));
    var after = 0;
    var misses = 0;
    while (!left) {
      final request = _request(
        connection,
        'GET',
        '$relayPath/v1/runs/${Uri.encodeComponent(id)}/events',
      )..headers['Accept'] = 'text/event-stream';
      if (after > 0) request.headers['Last-Event-ID'] = '$after';
      try {
        final response = await _client.send(request).timeout(timeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          _decode(await http.Response.fromStream(response));
        }
        await for (final event in serverSentEvents(
          _until(response.stream.timeout(quiet), gone),
        )) {
          if (event.id case final seen?) after = seen;
          misses = 0;
          switch (event.name) {
            case 'chunk':
              if (jsonOrNull(event.data) case final Map<String, dynamic> c) {
                yield c;
              }
            case 'failed':
              final data = jsonOrNull(event.data);
              final plain = event.data.trim();
              throw ApiException(
                _said(data) ??
                    (data == null && plain.isNotEmpty
                        ? plain
                        : 'The relay could not finish the answer.'),
              );
            case 'done' || 'cancelled':
              return;
          }
        }
      } on ApiException catch (error) {
        if ((error.status ?? 0) < 500) rethrow;
        // The relay failed for a moment: rejoin below.
      } on Exception {
        // Dropped or silent: rejoin below.
      }
      if (left) return;
      if (misses == rejoinDelays.length) {
        throw const AnswerStillRunning();
      }
      await Future.any([Future<void>.delayed(rejoinDelays[misses++]), gone]);
    }
  }

  /// A new id for one message's run, so a request sent twice starts it once.
  String _clientId() =>
      'c_${List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

  /// A `stream-chat` with `reset` and no message, which clears the history and answers with
  /// one closing chunk.
  @override
  Future<void> resetChat(String slug, String thread) => _events(
    '${_thread(slug, thread)}/stream-chat',
    {'reset': true},
    timeout,
  ).drain<void>();

  /// The presets live under `/api/system`, not `/api/v1`, and take the web UI's login, so they
  /// answer with the server's password, or on a server that has none.
  @override
  Future<List<SlashCommand>> slashCommands() async => [
    for (final json in jsonObjects(
      _field(
        await _session('GET', '/api/system/slash-command-presets'),
        'presets',
      ),
    ))
      ?SlashCommand.fromJson(json),
  ];

  @override
  Future<List<ScheduledJob>> scheduledJobs() async =>
      scheduledJobsOf(await _session('GET', '/api/scheduled-jobs'));

  /// The server answers a bare `OK`.
  @override
  Future<void> dropFrom(String slug, String thread, int chatId) => _session(
    'DELETE',
    '/api/workspace/${Uri.encodeComponent(slug)}/thread/'
        '${Uri.encodeComponent(thread)}/delete-edited-chats',
    body: {'startingId': chatId},
    emptyOk: true,
  );

  @override
  Future<void> setFeedback(String slug, int chatId, bool? good) => _session(
    'POST',
    '/api/workspace/${Uri.encodeComponent(slug)}/chat-feedback/$chatId',
    body: {'feedback': good},
  );

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
    DocMeta meta = const DocMeta(),
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
  List<DocEntry> _documents(Object? body) => [
    for (final json in jsonObjects(_field(body, 'documents')))
      DocEntry.fromJson(json),
  ];

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

  @override
  Future<List<SearchHit>> searchDocs(String slug, String query) async => [
    for (final json in jsonObjects(
      _field(
        await _send('POST', '${_workspace(slug)}/vector-search', {
          'query': query,
        }),
        'results',
      ),
    ))
      SearchHit.fromJson(json),
  ];

  @override
  Future<List<int>> exportChats(ChatExport format) =>
      _file('/api/v1/system/export-chats?type=${format.name}');

  @override
  Future<List<int>> generatedFile(String storageName) => _file(
    '/api/v1/document/generated-files/${Uri.encodeComponent(storageName)}',
  );

  /// A bare `GET` of [url], on any port of the server's host as [loadableImage] allows, read
  /// by [imageFrames]. The response is let go of at once when the subscription was cancelled
  /// while it waited for the headers, as an `async*` body would only notice at its next `yield`.
  @override
  Stream<Uint8List> answerImage(Uri url) {
    late final StreamController<Uint8List> out;
    StreamSubscription<Uint8List>? reading;
    var cancelled = false;
    Future<void> start() async {
      try {
        final connection = _current;
        if (!allowHttp && url.scheme == 'http') {
          throw const ApiException(
            'This device does not load images over plain http.',
          );
        }
        final response = await _fetch(
          connection,
          timeout,
          () => _client.send(http.Request('GET', url)),
        );
        final ok = response.statusCode >= 200 && response.statusCode < 300;
        if (cancelled || !ok) {
          unawaited(response.stream.listen(null).cancel());
        }
        if (cancelled) return;
        if (!ok) {
          throw ApiException(
            'The image could not be read: the server answered ${response.statusCode}.',
          );
        }
        reading = imageFrames(response.stream, response.headers['content-type'])
            .listen(
              out.add,
              onError: (Object error) => out.addError(
                error is http.ClientException
                    ? ApiException('The image was cut off: ${error.message}')
                    : error,
              ),
              onDone: out.close,
            );
      } on ApiException catch (error) {
        if (cancelled) return;
        out.addError(error);
        await out.close();
      }
    }

    out = StreamController(
      onListen: () => unawaited(start()),
      onCancel: () {
        cancelled = true;
        return reading?.cancel();
      },
    );
    return out.stream;
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
  Future<void> removeFolder(String name) => _send(
    'DELETE',
    '/api/v1/document/remove-folder',
    {'name': name},
    refused: 'The server did not delete the folder $name.',
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
    if (_field(answer, 'error') case final String error
        when error.trim().isNotEmpty) {
      throw ApiException(error.trim());
    }
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
  Future<List<Embed>> embeds() async => [
    for (final json in jsonObjects(
      _field(await _get(_current, '/api/v1/embed'), 'embeds'),
    ))
      Embed.fromJson(json),
  ];

  /// The server answers the new embed, or null with an `error` when it made none.
  @override
  Future<String> createEmbed(NewEmbed embed) async {
    final answer = await _send(
      'POST',
      '/api/v1/embed/new',
      embed.toJson(),
      refused: 'The server did not make the embed.',
    );
    if (_field(answer, 'error') case final String error
        when error.trim().isNotEmpty) {
      throw ApiException(error.trim());
    }
    return switch (_field(answer, 'embed')) {
      {'uuid': final String uuid} => uuid,
      _ => throw const ApiException('The server did not make the embed.'),
    };
  }

  @override
  Future<void> updateEmbed(
    String uuid, {
    bool? enabled,
    EmbedMode? mode,
  }) async {
    final answer = await _send(
      'POST',
      '/api/v1/embed/${Uri.encodeComponent(uuid)}',
      {'enabled': ?enabled, 'chat_mode': ?mode?.name},
      refused: 'The server did not change the embed.',
    );
    if (_field(answer, 'error') case final String error
        when error.trim().isNotEmpty) {
      throw ApiException(error.trim());
    }
  }

  @override
  Future<void> deleteEmbed(String uuid) => _send(
    'DELETE',
    '/api/v1/embed/${Uri.encodeComponent(uuid)}',
    null,
    refused: 'The server did not delete the embed.',
  );

  @override
  Future<List<EmbedChat>> embedChats(String uuid) async => [
    for (final json in jsonObjects(
      _field(
        await _get(
          _current,
          '/api/v1/embed/${Uri.encodeComponent(uuid)}/chats',
        ),
        'chats',
      ),
    ))
      EmbedChat.fromJson(json),
  ];

  /// `/v1/admin/workspace-chats` answers every workspace's chats on any server, though its
  /// other `/v1/admin` routes refuse one with a single user.
  @override
  Future<ChatLog> workspaceChats({int page = 0}) async => ChatLog.fromJson(
    await _send('POST', '/api/v1/admin/workspace-chats', {'offset': page}),
  );

  @override
  Future<bool> relayFound({bool again = false}) {
    if (again) _relays.remove(_current.withPassword(null));
    return _isRelay(_current);
  }

  @override
  Future<int> vectorCount() async => switch (_field(
    await _get(_current, '/api/v1/system/vector-count'),
    'vectorCount',
  )) {
    final num count => count.toInt(),
    _ => throw const ApiException(_refused),
  };

  /// The connection in use.
  Connection get _current =>
      _secure(_holder.current ?? (throw const NotConfigured()));

  /// [connection], or an [ApiException] when it is `http://` and [allowHttp] is false.
  Connection _secure(Connection connection) {
    if (!allowHttp && connection.uri.scheme == 'http') {
      throw const ApiException(
        'Use an https:// address. This device does not sign in over plain http.',
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

  /// The decoded JSON of a [method] to [path], one of the web UI's own routes, with [body] as
  /// JSON, on the connection in use or [on], signed in with the connection's password in place
  /// of the key, or without credentials when no password is saved. A refused token is forgotten
  /// and the call made once more with a new one. A server that requires credentials says so
  /// with 401 or 403.
  Future<Object?> _session(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool emptyOk = false,
    Connection? on,
  }) async {
    final connection = on ?? _current;
    final signsIn = connection.password != null;
    for (var again = false; ; again = true) {
      final token = signsIn ? await _token(connection) : null;
      try {
        return await _call(
          connection,
          timeout,
          () async {
            final request = _request(connection, method, path, body);
            if (token == null) {
              request.headers.remove('Authorization');
            } else {
              request.headers['Authorization'] = 'Bearer $token';
            }
            return http.Response.fromStream(await _client.send(request));
          },
          emptyOk: emptyOk,
          rejected: signsIn ? _passwordRefused : _needsPassword,
        );
      } on ApiException catch (error) {
        final refused = error.status == 401 || error.status == 403;
        if (!signsIn || again || !refused) rethrow;
        _tokens.remove(connection);
      }
    }
  }

  /// The web UI's login token for [connection], signing in with its password when there is none
  /// yet. Without a password this fails with status 401, and with a refused one with the
  /// server's 401, or 403 when it answers that the password is not valid.
  Future<String> _token(Connection connection) async {
    if (_tokens[connection] case final token?) return token;
    final password =
        connection.password ??
        (throw const ApiException(_needsPassword, status: 401));
    final body = await _call(
      connection,
      timeout,
      () => _client.post(
        Uri.parse('${connection.baseUrl}/api/request-token'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'password': password}),
      ),
      rejected: _passwordRefused,
    );
    if (body is! Map || body['valid'] != true) {
      throw const ApiException(_passwordRefused, status: 403);
    }
    final token = body['token'];
    if (token is! String || token.isEmpty) {
      throw const ApiException(_passwordRefused, status: 403);
    }
    return _tokens[connection] = token;
  }

  /// The decoded JSON of a GET to [path] on [connection].
  Future<Object?> _get(Connection connection, String path) => _call(
    connection,
    timeout,
    () => _client.get(
      Uri.parse('${connection.baseUrl}$path'),
      headers: _headers(connection),
    ),
  );

  /// The events of a POST of [body] to [path], whose answer streams server-sent events. A
  /// failed status is an [ApiException] with the server's words, as is a stream cut off. A
  /// cancel lets go of the response at once, even before the first event, as the `async*`
  /// readers of [chatEvents] would not until their next `yield`: the server stops answering
  /// when the connection closes.
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
    Future<void> fail(Object error) async {
      if (cancelled) return;
      out.addError(switch (error) {
        http.ClientException(:final message) => ApiException(
          'The answer was cut off: $message',
        ),
        TimeoutException() => const ApiException(
          'The server sent nothing for too long, so the answer was given up.',
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
        final answer = await _fetch(
          connection,
          limit,
          () => _client.send(request),
        );
        if (cancelled) {
          unawaited(answer.stream.listen(null).cancel());
          return;
        }
        if (answer.statusCode < 200 || answer.statusCode >= 300) {
          _decode(await http.Response.fromStream(answer));
        }
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
    final connection = on ?? _current;
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

  /// The decoded JSON of the response [send] gets, with failures in plain words. [emptyOk],
  /// [refused] and [rejected] are as for [_decode].
  Future<Object?> _call(
    Connection connection,
    Duration limit,
    Future<http.Response> Function() send, {
    bool emptyOk = false,
    String refused = _refused,
    String rejected = _keyRejected,
  }) async => _decode(
    await _fetch(connection, limit, send),
    emptyOk: emptyOk,
    refused: refused,
    rejected: rejected,
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
      'Could not reach the server: $message'
      '${browserOrigin == null ? '' : '. A browser also says this when the server does not allow requests from $browserOrigin.'}',
    ),
    _ => ApiException('Could not reach the server: $error'),
  };

  static const _refused = 'The server refused the request.';
  static const _keyRejected = 'The server rejected the key.';
  static const _needsPassword =
      'This needs the server password. Add it in Settings.';
  static const _passwordRefused = 'The server did not accept the password.';

  /// The decoded JSON of [response], or null for a success that is empty or the bare status
  /// text `OK` when [emptyOk], as a delete answers. An answer with `success: false` fails, even with HTTP 200, with the server's reason
  /// or else [refused]. A 401 or 403 fails with [rejected], whatever the server said.
  Object? _decode(
    http.Response response, {
    bool emptyOk = false,
    String refused = _refused,
    String rejected = _keyRejected,
  }) {
    final status = response.statusCode;
    final body = _json(response);
    if (status == 401 || status == 403) {
      throw ApiException(rejected, status: status);
    }
    if (status < 200 || status >= 300) {
      throw ApiException(
        _said(body) ?? 'The server answered HTTP $status.',
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
      throw ApiException(_said(body) ?? refused, status: status);
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

/// [source] until [gone] completes, when it is cancelled and the stream ends.
Stream<T> _until<T>(Stream<T> source, Future<void> gone) {
  StreamSubscription<T>? from;
  late final StreamController<T> out;
  out = StreamController<T>(
    onListen: () {
      from = source.listen(out.add, onError: out.addError, onDone: out.close);
      unawaited(
        gone.then((_) async {
          await from?.cancel();
          await out.close();
        }),
      );
    },
    onPause: () => from?.pause(),
    onResume: () => from?.resume(),
    onCancel: () => from?.cancel(),
  );
  return out.stream;
}
