import 'package:http/http.dart' as http;

import '../core/activity.dart';
import '../core/companion.dart';
import '../core/connection.dart';
import '../core/library.dart';
import '../core/memory.dart';
import '../core/ports.dart';
import '../core/schedule.dart';
import '../core/toolkit.dart';
import 'companion_client.dart';

/// [ToolkitApi] over the toolkit's client API, on the AnythingLLM server's host at
/// [toolkitCompanion]'s port, with the connection's developer key on every call but `/health`.
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

  @override
  Future<Set<String>?> features({bool again = false}) =>
      _companion.features(again: again);

  @override
  Future<List<ScheduledJob>> scheduledJobs() async =>
      scheduledJobsOf(await _companion.json('GET', ['jobs']));

  @override
  Future<LibraryContents> library() async =>
      libraryOf(await _companion.json('GET', ['library']));

  @override
  Future<ActivityEvents> activity({String? before, int limit = 50}) async =>
      activityOf(
        await _companion.json(
          'GET',
          ['activity'],
          query: {'limit': '$limit', 'before': ?before},
        ),
      );

  @override
  Future<List<JobRun>> jobRuns(String id, {int limit = 5}) async => jobRunsOf(
    await _companion.json(
      'GET',
      ['jobs', id, 'runs'],
      query: {'limit': '$limit'},
    ),
  );

  // The calls below answer with what they did, which the app reads again as a list of jobs, so
  // none decodes the answer.
  @override
  Future<void> createJob(JobDraft draft, {required String key}) async {
    await _companion.call(
      'POST',
      ['jobs'],
      body: draft.toJson(),
      headers: {'Idempotency-Key': key},
    );
  }

  @override
  Future<void> updateJob(String id, JobDraft draft) async {
    await _companion.call('PUT', ['jobs', id], body: draft.toJson());
  }

  @override
  Future<void> setJobEnabled(String id, bool enabled) async {
    await _companion.call('PUT', ['jobs', id], body: {'enabled': enabled});
  }

  @override
  Future<void> deleteJob(String id) async {
    await _companion.call('DELETE', ['jobs', id]);
  }

  @override
  Future<void> runJob(String id, {required String key}) async {
    await _companion.call(
      'POST',
      ['jobs', id, 'run'],
      headers: {'Idempotency-Key': key},
    );
  }

  @override
  Future<MemorySwitches> memorySwitches() async => MemorySwitches.fromJson(
    await _companion.json('GET', ['memory-switches']),
  );

  @override
  Future<void> setMemorySwitches({bool? enabled, bool? learn}) =>
      _companion.json(
        'PUT',
        ['memory-switches'],
        body: {'enabled': ?enabled, 'learn': ?learn},
      );

  @override
  Future<SavedMemories> savedMemories(String slug) async =>
      SavedMemories.fromJson(
        await _companion.json('GET', ['workspaces', slug, 'memories']),
      );

  @override
  Future<SavedMemory> addMemory(
    String slug,
    String text, {
    required bool global,
  }) async => _memory(
    await _companion.json(
      'POST',
      ['workspaces', slug, 'memories'],
      body: {'content': text, 'scope': global ? 'global' : 'workspace'},
    ),
  );

  @override
  Future<SavedMemory> editMemory(int id, String text) async => _memory(
    await _companion.json('PUT', ['memories', '$id'], body: {'content': text}),
  );

  @override
  Future<void> deleteMemory(int id) =>
      _companion.json('DELETE', ['memories', '$id']);

  @override
  Future<SavedMemory> moveMemory(int id, {String? toWorkspace}) async =>
      _memory(
        await _companion.json(
          'POST',
          ['memories', '$id', 'move'],
          body: {'workspace': toWorkspace},
        ),
      );

  /// The memory an answer holds under `memory`.
  static SavedMemory _memory(Object? body) =>
      SavedMemory.fromJson(body is Map ? body['memory'] : null) ??
      (throw const ApiException('The toolkit did not answer with the memory.'));
}
