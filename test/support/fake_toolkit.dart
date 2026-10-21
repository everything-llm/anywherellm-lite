import 'package:anywherellm/core/activity.dart';
import 'package:anywherellm/core/companion.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/memory.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/core/toolkit.dart';

import 'fake_companion.dart';

/// The toolkit's `CLIENT_ALLOW`, which its `install` writes as `BRIDGE_ALLOW`: what the app
/// calls.
/// [connection] in use, with the toolkit at [toolkitAt], as a pairing code says where it runs.
ConnectionHolder pairedHolder(Connection connection, Uri toolkitAt) =>
    ConnectionHolder(connection)
      ..companions = {toolkitCompanion.code: toolkitAt};

const liteBridgeAllow =
    '/workspaces, /memories, GET /admin/system-preferences-for, '
    'POST /admin/system-preferences, /scheduled-jobs';

/// A [ToolkitApi] for widget tests that keeps the saved memories and the scheduled jobs in
/// memory. It is [present] unless a test makes it absent, as beside a stock AnythingLLM, and
/// serves every feature in [served]: by default the memories and the jobs, to read only; add
/// [ToolkitFeature.jobsWrite] to let them be changed.
class FakeToolkit with FakeCompanion implements ToolkitApi {
  FakeToolkit({this.present = true});

  @override
  bool present;

  @override
  Companion get companion => toolkitCompanion;

  @override
  Set<String> served = {ToolkitFeature.memories, ToolkitFeature.jobs};

  @override
  Future<List<ScheduledJob>> scheduledJobs() =>
      run('scheduledJobs', () => jobs);

  /// What [memorySwitches] answers, and [setMemorySwitches] changes.
  MemorySwitches switches = const MemorySwitches(enabled: true, learn: true);

  /// The saved memories for every workspace.
  final List<SavedMemory> globalMemories = [];

  /// Each workspace's own saved memories, by slug.
  final Map<String, List<SavedMemory>> workspaceMemories = {};

  /// An id no saved memory has, as the server numbers them.
  int get _nextMemory =>
      [
        0,
        for (final list in [globalMemories, ...workspaceMemories.values])
          for (final m in list) m.id,
      ].reduce((a, b) => a > b ? a : b) +
      1;

  @override
  Future<MemorySwitches> memorySwitches() =>
      run('memorySwitches', () => switches);

  @override
  Future<void> setMemorySwitches({bool? enabled, bool? learn}) => run(
    'setMemorySwitches',
    () => switches = MemorySwitches(
      enabled: enabled ?? switches.enabled,
      learn: learn ?? switches.learn,
    ),
    [
      ?enabled == null ? null : 'enabled=$enabled',
      ?learn == null ? null : 'learn=$learn',
    ].join(','),
  );

  /// Refuses a saved-memory call while they are off, as the server does.
  void _memoriesOn() {
    if (!switches.enabled) {
      throw const ApiException('Personalization is disabled.', status: 403);
    }
  }

  /// The list a saved memory for every workspace, or for [slug], goes in.
  List<SavedMemory> _memories(String? slug) => slug == null
      ? globalMemories
      : workspaceMemories.putIfAbsent(slug, () => []);

  /// Adds [memory] to the list for every workspace, or for [slug], unless it is full, as the
  /// server refuses it.
  SavedMemory _keepMemory(SavedMemory memory, String? slug) {
    final list = _memories(slug);
    final limit = slug == null ? globalMemoryLimit : workspaceMemoryLimit;
    if (list.length >= limit) {
      throw ApiException(
        'Maximum ${slug == null ? 'global' : 'workspace'} memory limit ($limit) reached.',
        status: 400,
      );
    }
    list.add(memory);
    return memory;
  }

  /// The list that holds saved memory [id], or a 404.
  List<SavedMemory> _holding(int id) =>
      [
        globalMemories,
        ...workspaceMemories.values,
      ].where((list) => list.any((m) => m.id == id)).firstOrNull ??
      (throw const ApiException('Memory not found.', status: 404));

  @override
  Future<SavedMemories> savedMemories(String slug) => run('savedMemories', () {
    _memoriesOn();
    return SavedMemories(
      global: [...globalMemories],
      workspace: [...?workspaceMemories[slug]],
    );
  }, slug);

  @override
  Future<SavedMemory> addMemory(
    String slug,
    String text, {
    required bool global,
  }) => run('addMemory', () {
    _memoriesOn();
    return _keepMemory(
      SavedMemory(id: _nextMemory, text: text, global: global),
      global ? null : slug,
    );
  }, text);

  @override
  Future<SavedMemory> editMemory(int id, String text) => run('editMemory', () {
    _memoriesOn();
    final list = _holding(id);
    final at = list.indexWhere((m) => m.id == id);
    return list[at] = SavedMemory(id: id, text: text, global: list[at].global);
  }, '$id');

  @override
  Future<void> deleteMemory(int id) => run('deleteMemory', () {
    _memoriesOn();
    _holding(id).removeWhere((m) => m.id == id);
  }, '$id');

  @override
  Future<SavedMemory> moveMemory(int id, {String? toWorkspace}) =>
      run('moveMemory', () {
        _memoriesOn();
        final list = _holding(id);
        final memory = list.firstWhere((m) => m.id == id);
        final moved = _keepMemory(
          SavedMemory(id: id, text: memory.text, global: toWorkspace == null),
          toWorkspace,
        );
        list.remove(memory);
        return moved;
      }, '$id:${toWorkspace ?? 'global'}');

  /// What [scheduledJobs] answers.
  List<ScheduledJob> jobs = const [];

  /// What [activity] answers, newest first, paged [activityPageSize] at a time from the event
  /// whose id is `before`.
  List<ActivityEvent> activityEvents = const [];
  int activityPageSize = 50;

  @override
  Future<ActivityEvents> activity({String? before, int limit = 50}) =>
      run('activity', () {
        final from = before == null
            ? 0
            : activityEvents.indexWhere((e) => e.id == before) + 1;
        final size = activityPageSize < limit ? activityPageSize : limit;
        final page = activityEvents.skip(from).take(size).toList();
        return ActivityEvents(
          page,
          more: from + page.length < activityEvents.length,
        );
      }, before ?? '');

  /// Each job's runs by id, newest first, which [jobRuns] answers.
  final Map<String, List<JobRun>> runRecords = {};

  /// The status a run started by [runJob] has when read: `completed` unless a test says
  /// `running` or `failed`.
  String runStatus = 'completed';

  int _nextJob = 1;

  ScheduledJob _job(String id) =>
      jobs.where((j) => j.id == id).firstOrNull ??
      (throw const ApiException('Job not found.', status: 404));

  void _replace(String id, ScheduledJob Function(ScheduledJob) change) {
    _job(id);
    jobs = [for (final j in jobs) j.id == id ? change(j) : j];
  }

  /// Refuses a schedule AnythingLLM would, in its words: one that is not five cron fields.
  void _checkCron(String cron) {
    if (cron.trim().split(RegExp(r'\s+')).length != 5) {
      throw const ApiException('Invalid cron expression.', status: 400);
    }
  }

  @override
  Future<List<JobRun>> jobRuns(String id, {int limit = 5}) =>
      run('jobRuns', () => [...?runRecords[id]].take(limit).toList(), id);

  @override
  Future<void> createJob(JobDraft draft) => run('createJob', () {
    _checkCron(draft.cron);
    jobs = [
      ...jobs,
      ScheduledJob(
        id: '${_nextJob++}',
        name: draft.name,
        prompt: draft.prompt,
        cron: draft.cron,
      ),
    ];
  }, '${draft.name}|${draft.cron}');

  @override
  Future<void> updateJob(String id, JobDraft draft) => run('updateJob', () {
    _checkCron(draft.cron);
    _replace(
      id,
      (j) => _with(j, name: draft.name, prompt: draft.prompt, cron: draft.cron),
    );
  }, '$id|${draft.name}|${draft.cron}');

  @override
  Future<void> setJobEnabled(String id, bool enabled) => run(
    'setJobEnabled',
    () => _replace(id, (j) => _with(j, enabled: enabled)),
    '$id=$enabled',
  );

  /// [job] with what is given changed.
  static ScheduledJob _with(
    ScheduledJob job, {
    String? name,
    String? prompt,
    String? cron,
    bool? enabled,
  }) => ScheduledJob(
    id: job.id,
    name: name ?? job.name,
    prompt: prompt ?? job.prompt,
    tools: job.tools,
    cron: cron ?? job.cron,
    enabled: enabled ?? job.enabled,
    nextRun: job.nextRun,
    lastRun: job.lastRun,
    lastStatus: job.lastStatus,
  );

  @override
  Future<void> deleteJob(String id) => run('deleteJob', () {
    _job(id);
    jobs = [
      for (final j in jobs)
        if (j.id != id) j,
    ];
    runRecords.remove(id);
  }, id);

  /// Starts a run with [runStatus], or, as AnythingLLM skips one while another runs, fails.
  @override
  Future<void> runJob(String id) => run('runJob', () {
    _job(id);
    if (runRecords[id]?.firstOrNull?.running ?? false) {
      throw const ApiException('It is already running.');
    }
    runRecords[id] = [
      JobRun(startedAt: DateTime.now().toUtc(), status: runStatus),
      ...?runRecords[id],
    ];
  }, id);
}
