import 'package:http/http.dart' as http;

import '../core/activity.dart';
import '../core/asks.dart';
import '../core/companion.dart';
import '../core/connection.dart';
import '../core/json.dart';
import '../core/library.dart';
import '../core/memory.dart';
import '../core/ports.dart';
import '../core/schedule.dart';
import '../core/toolkit.dart';
import 'companion_client.dart';

/// [ToolkitApi] over the toolkit's bridge, at the address a pairing code gave
/// [toolkitCompanion], with the connection's developer key on every call but `/health`.
/// Each call is one of AnythingLLM's internal routes, without its `/api`, answered in
/// AnythingLLM's own JSON.
class HttpToolkitApi implements ToolkitApi {
  HttpToolkitApi({
    required ConnectionHolder holder,
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
    Duration healthTimeout = const Duration(seconds: 5),
  }) : _companion = CompanionClient(
         toolkitCompanion,
         holder: holder,
         client: client ?? http.Client(),
         timeout: timeout,
         healthTimeout: healthTimeout,
       );

  final CompanionClient _companion;

  @override
  Companion get companion => _companion.companion;

  /// The features the routes the bridge allows let through, and those it serves itself.
  @override
  Future<Set<String>?> features({bool again = false}) async {
    final health = await _companion.health(again: again);
    if (health == null) return null;
    return {
      ...bridgeFeatures(bridgeRules(health)),
      if (health case {'asks': true}) ToolkitFeature.asks,
    };
  }

  @override
  Future<List<ScheduledJob>> scheduledJobs() async =>
      scheduledJobsOf(await _json('GET', ['scheduled-jobs']));

  @override
  Future<LibraryContents> library() async =>
      libraryOf(await _json('GET', ['library']));

  @override
  Future<ActivityEvents> activity({String? before, int limit = 50}) async =>
      activityOf(
        await _json(
          'GET',
          ['activity'],
          query: {'limit': '$limit', 'before': ?before},
        ),
      );

  /// The newest [limit] of the 50 runs AnythingLLM lists.
  @override
  Future<List<JobRun>> jobRuns(String id, {int limit = 5}) async => jobRunsOf(
    await _json('GET', ['scheduled-jobs', id, 'runs']),
    limit: limit,
  );

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

  // The requests and the allowed addresses are the bridge's own, not AnythingLLM's.
  @override
  Future<Ask> ask(String id) async => _ask(await _json('GET', ['asks', id]));

  @override
  Future<void> decide(String id, AskDecision decision) =>
      _json('POST', ['asks', id], body: {'decision': decision.name});

  @override
  Future<List<AllowedOrigin>> allowedOrigins() async =>
      allowedOriginsOf(await _json('GET', ['allowed']));

  // An origin holds slashes, so it goes in the query, not the path.
  @override
  Future<List<AllowedOrigin>> forgetOrigin(String origin) async =>
      allowedOriginsOf(
        await _json('DELETE', ['allowed'], query: {'origin': origin}),
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
    final answer = await _companion.json(
      method,
      path,
      query: query,
      body: body,
    );
    if (answer is Map && answer['success'] == false) {
      throw ApiException(saidIn(answer) ?? refused);
    }
    return answer;
  }

  /// The request an answer holds under `ask`.
  static Ask _ask(Object? body) =>
      askOf(body) ??
      (throw const ApiException(
        'The toolkit did not answer with the request.',
      ));

  /// The memory an answer holds under `memory`.
  static SavedMemory _memory(Object? body) =>
      SavedMemory.fromJson(body is Map ? body['memory'] : null) ??
      (throw const ApiException('AnythingLLM did not answer with the memory.'));
}
