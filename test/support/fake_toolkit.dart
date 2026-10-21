import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/memory.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/core/skill_pages.dart';
import 'package:anywherellm/core/toolkit.dart';

/// [connection] in use, with the toolkit at [toolkitAt], as a pairing code says where it runs.
ConnectionHolder pairedHolder(Connection connection, Uri toolkitAt) =>
    ConnectionHolder(connection)
      ..companions = {toolkitCompanion.code: toolkitAt};

/// The toolkit's `CLIENT_ALLOW`, which its `install` writes as `BRIDGE_ALLOW`: what the app
/// calls.
const liteBridgeAllow =
    '/workspaces, /memories, GET /admin/system-preferences-for, '
    'POST /admin/system-preferences, /scheduled-jobs';

/// A [ToolkitApi] for widget tests that keeps the saved memories and the scheduled jobs in
/// memory. It is [present] unless a test makes it absent, as beside a stock AnythingLLM, and
/// serves every feature in [served]: by default the memories and the jobs, to read only; add
/// [ToolkitFeature.jobsWrite] to let them be changed. What [features] answers is remembered until
/// asked `again`. Every call is recorded in [calls] as `name` or `name:arg`, and an error in
/// [errors] under a method's name makes it fail.
class FakeToolkit implements ToolkitApi {
  FakeToolkit({this.present = true});

  /// Whether `/health` names the toolkit.
  bool present;

  /// The features `/health` names while [present].
  Set<String> served = {ToolkitFeature.memories, ToolkitFeature.jobs};

  final List<String> calls = [];
  final Map<String, Exception> errors = {};

  Set<String>? _remembered;
  bool _known = false;

  @override
  Future<Set<String>?> features({bool again = false}) async {
    calls.add('features${again ? ':again' : ''}');
    if (again || !_known) {
      _known = true;
      _remembered = present ? {...served} : null;
    }
    return _remembered;
  }

  /// Records [name] with [arg], fails it with its error in [errors], else answers [value].
  Future<T> _run<T>(String name, T Function() value, [String? arg]) async {
    calls.add(arg == null ? name : '$name:$arg');
    if (errors[name] case final error?) throw error;
    return value();
  }

  /// What [pages] answers: where the Library and the Vault are.
  SkillPages skillPages = const {};

  @override
  Future<SkillPages> pages() => _run('pages', () => skillPages);

  @override
  Future<List<ScheduledJob>> scheduledJobs() =>
      _run('scheduledJobs', () => jobs);

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
      _run('memorySwitches', () => switches);

  @override
  Future<void> setMemorySwitches({bool? enabled, bool? learn}) => _run(
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
  Future<SavedMemories> savedMemories(String slug) => _run('savedMemories', () {
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
  }) => _run('addMemory', () {
    _memoriesOn();
    return _keepMemory(
      SavedMemory(id: _nextMemory, text: text, global: global),
      global ? null : slug,
    );
  }, text);

  @override
  Future<SavedMemory> editMemory(int id, String text) => _run('editMemory', () {
    _memoriesOn();
    final list = _holding(id);
    final at = list.indexWhere((m) => m.id == id);
    return list[at] = SavedMemory(id: id, text: text, global: list[at].global);
  }, '$id');

  @override
  Future<void> deleteMemory(int id) => _run('deleteMemory', () {
    _memoriesOn();
    _holding(id).removeWhere((m) => m.id == id);
  }, '$id');

  @override
  Future<SavedMemory> moveMemory(int id, {String? toWorkspace}) =>
      _run('moveMemory', () {
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
  Future<List<JobRun>> jobRuns(String id) =>
      _run('jobRuns', () => [...?runRecords[id]].take(runsRead).toList(), id);

  @override
  Future<void> createJob(JobDraft draft) => _run('createJob', () {
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
  Future<void> updateJob(String id, JobDraft draft) => _run('updateJob', () {
    _checkCron(draft.cron);
    _replace(
      id,
      (j) => _with(j, name: draft.name, prompt: draft.prompt, cron: draft.cron),
    );
  }, '$id|${draft.name}|${draft.cron}');

  @override
  Future<void> setJobEnabled(String id, bool enabled) => _run(
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
  Future<void> deleteJob(String id) => _run('deleteJob', () {
    _job(id);
    jobs = [
      for (final j in jobs)
        if (j.id != id) j,
    ];
    runRecords.remove(id);
  }, id);

  /// Starts a run with [runStatus], or, as AnythingLLM skips one while another runs, fails.
  @override
  Future<void> runJob(String id) => _run('runJob', () {
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
