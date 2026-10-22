import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/companion.dart';
import '../core/connection.dart';
import '../core/json.dart';
import '../core/memory.dart';
import '../core/ports.dart';
import '../core/schedule.dart';
import '../core/skill_pages.dart';
import '../core/toolkit.dart';
import 'unreachable.dart';

/// [ToolkitApi] over the toolkit's bridge, at the address a pairing code gave
/// [toolkitCompanion], over the connection the holder has when each call is made: its `/health`,
/// asked without the key and remembered by the toolkit's address, and every other call with the
/// connection's developer key, only where the key may go ([keySafe]). Each call is one of
/// AnythingLLM's internal routes, without its `/api`, answered in AnythingLLM's own JSON. An
/// error message names the toolkit and never contains the key.
class HttpToolkitApi implements ToolkitApi {
  HttpToolkitApi({required this._holder, http.Client? client})
    : _client = client ?? http.Client();

  /// How long a call may take.
  static const timeout = Duration(seconds: 15);

  /// How long `/health` may take before the toolkit is taken to be absent.
  static const healthTimeout = Duration(seconds: 5);

  final ConnectionHolder _holder;

  /// What every call goes through.
  final http.Client _client;

  /// Each `/health` answer, null when the toolkit is not there, by the toolkit's address.
  final _found = <String, Future<Object?>>{};

  /// Where the toolkit runs beside the server in use ([ConnectionHolder.addressOf]). Null with no
  /// server.
  Uri? get _address => _holder.addressOf(toolkitCompanion);

  /// The features the routes the bridge allows let through, from its `/health` at [_address].
  /// Null when it is not there, with no server, or where the key could not go ([keySafe]).
  @override
  Future<Set<String>?> features({bool again = false}) async {
    final at = _address;
    if (at == null || !keySafe(at)) return null;
    final key = '$at';
    if (again) _found.remove(key);
    final health = await (_found[key] ??= _health(at));
    if (health == null) return null;
    return {
      ...bridgeFeatures(bridgeRules(health)),
      if (health case {'pages': true}) ToolkitFeature.pages,
    };
  }

  /// The toolkit's `/health` at [at], or null for anything else that answers, or nothing.
  Future<Object?> _health(Uri at) async {
    try {
      final response = await _client
          .get(
            under(at, const ['health']),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(healthTimeout);
      if (response.statusCode != 200) return null;
      final json = _bodyOf(response);
      return toolkitCompanion.isHealth(json) ? json : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<SkillPages> pages() async =>
      skillPagesOf(await _json('GET', ['pages']));

  @override
  Future<List<ScheduledJob>> scheduledJobs() async =>
      scheduledJobsOf(await _json('GET', ['scheduled-jobs']));

  @override
  Future<List<JobRun>> jobRuns(String id) async =>
      jobRunsOf(await _json('GET', ['scheduled-jobs', id, 'runs']));

  // The calls below answer with what they did, which the app reads again as a list of jobs.
  @override
  Future<void> createJob(JobDraft draft) async {
    await _json('POST', ['scheduled-jobs', 'new'], body: draft.toJson());
  }

  @override
  Future<void> updateJob(String id, JobDraft draft) async {
    await _json('PUT', ['scheduled-jobs', id], body: draft.toJson());
  }

  @override
  Future<void> setJobEnabled(String id, bool enabled) async {
    await _json('PUT', ['scheduled-jobs', id], body: {'enabled': enabled});
  }

  @override
  Future<void> deleteJob(String id) async {
    await _json('DELETE', [
      'scheduled-jobs',
      id,
    ], refused: 'That task is gone already.');
  }

  @override
  Future<void> runJob(String id) async {
    final answer = await _json('POST', ['scheduled-jobs', id, 'trigger']);
    if (answer is Map && answer['skipped'] == true) {
      throw const ApiException('It is already running.');
    }
  }

  @override
  Future<MemorySwitches> memorySwitches() async => MemorySwitches.fromJson(
    await _json(
      'GET',
      ['admin', 'system-preferences-for'],
      query: {
        'labels': '${MemorySwitches.enabledLabel},${MemorySwitches.learnLabel}',
      },
    ),
  );

  /// Each switch is a system preference AnythingLLM keeps as text.
  @override
  Future<void> setMemorySwitches({bool? enabled, bool? learn}) => _json(
    'POST',
    ['admin', 'system-preferences'],
    body: MemorySwitches.preferences(enabled: enabled, learn: learn),
  );

  @override
  Future<SavedMemories> savedMemories(String slug) async =>
      SavedMemories.fromJson(
        await _json('GET', ['workspaces', slug, 'memories']),
      );

  @override
  Future<SavedMemory> addMemory(
    String slug,
    String text, {
    required bool global,
  }) async => _memory(
    await _json(
      'POST',
      ['workspaces', slug, 'memories'],
      body: {'content': text, 'scope': global ? 'global' : 'workspace'},
    ),
  );

  @override
  Future<SavedMemory> editMemory(int id, String text) async =>
      _memory(await _json('PUT', ['memories', '$id'], body: {'content': text}));

  @override
  Future<void> deleteMemory(int id) => _json('DELETE', ['memories', '$id']);

  @override
  Future<SavedMemory> moveMemory(int id, {String? toWorkspace}) async =>
      _memory(
        await _json('POST', [
          'memories',
          '$id',
          ...switch (toWorkspace) {
            final slug? => ['demote', slug],
            null => ['promote'],
          },
        ]),
      );

  /// The decoded JSON of a [method] to AnythingLLM's [path] through the bridge. AnythingLLM
  /// refuses some calls with `success: false` at HTTP 200, which fails in its words, or else
  /// [refused].
  Future<Object?> _json(
    String method,
    List<String> path, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
    String refused = 'AnythingLLM did not do it.',
  }) async {
    final response = await _call(method, path, query: query, body: body);
    final answer =
        _bodyOf(response) ??
        (throw ApiException(
          '${toolkitCompanion.name} did not answer with JSON.',
        ));
    if (answer is Map && answer['success'] == false) {
      throw ApiException(saidIn(answer) ?? refused);
    }
    return answer;
  }

  /// The connection in use and the toolkit's [_address], where its key may go ([keySafe]).
  (Connection, Uri) get _target {
    final connection = _holder.current ?? (throw const NotConfigured());
    final at = _address!;
    if (!keySafe(at)) throw const ApiException(plainHttpRefused);
    return (connection, at);
  }

  /// A [method] to [path] with the key, failing with the toolkit's words on any status but a
  /// success.
  Future<http.Response> _call(
    String method,
    List<String> path, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
  }) async {
    final (connection, at) = _target;
    final request = http.Request(method, under(at, path, query))
      ..headers['Authorization'] = 'Bearer ${connection.apiKey}'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    final response = await _fetch(
      () async => http.Response.fromStream(await _client.send(request)),
    );
    final status = response.statusCode;
    if (status >= 200 && status < 300) return response;
    if (status == 401) {
      throw ApiException(
        '${toolkitCompanion.name} did not accept the key.',
        status: 401,
      );
    }
    throw ApiException(
      _said(response) ?? '${toolkitCompanion.name} answered HTTP $status.',
      status: status,
    );
  }

  /// What [send] gets within [timeout], or an [ApiException] in plain words.
  Future<T> _fetch<T>(Future<T> Function() send) async {
    try {
      return await send().timeout(timeout);
    } on Exception catch (error) {
      final name = toolkitCompanion.name;
      throw unreachable(
        error,
        name: name,
        where: '${name.toLowerCase()} on ${_address?.host}',
        limit: timeout,
      );
    }
  }

  /// The decoded JSON of [response], or null when it is not JSON.
  static Object? _bodyOf(http.Response response) =>
      jsonOrNull(utf8.decode(response.bodyBytes, allowMalformed: true));

  static final _endsSentence = RegExp(r'[.?!]$');

  /// The `error` the toolkit put in a failed answer, with its first letter raised and a full
  /// stop unless it ends with one, a `?` or a `!`.
  static String? _said(http.Response response) {
    final said = switch (_bodyOf(response)) {
      {'error': final String error} => error.trim(),
      _ => '',
    };
    if (said.isEmpty) return null;
    final raised = '${said[0].toUpperCase()}${said.substring(1)}';
    return _endsSentence.hasMatch(raised) ? raised : '$raised.';
  }

  /// The memory an answer holds under `memory`.
  static SavedMemory _memory(Object? body) =>
      SavedMemory.fromJson(body is Map ? body['memory'] : null) ??
      (throw const ApiException('AnythingLLM did not answer with the memory.'));
}
