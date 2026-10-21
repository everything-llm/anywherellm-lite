import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/activity.dart';
import '../../core/ports.dart';
import '../../core/schedule.dart';
import '../../core/skill_pages.dart';
import '../../core/toolkit.dart';
import 'companion_watch.dart';
import 'notice.dart';
import 'settings_controller.dart';

/// What the app knows of the toolkit beside the server in use: whether it is there, what its
/// bridge lets through, the scheduled jobs, which, where it allows, the app makes, changes,
/// runs and deletes.
/// Another server starts it afresh, and Test connection asks again whether the toolkit is
/// there.
class ToolkitController extends ChangeNotifier with CompanionWatch {
  ToolkitController(this._api, SettingsController settings) {
    watch(_api, settings);
  }

  final ToolkitApi _api;

  /// Whether the toolkit serves the saved memories, which the Memory page shows.
  bool get memories => serves(ToolkitFeature.memories);

  /// Whether the toolkit lists the scheduled jobs, which Upcoming shows.
  bool get jobsServed => serves(ToolkitFeature.jobs);

  /// Whether the toolkit lets jobs be made, changed, run and deleted, not only listed.
  bool get jobsWritable => serves(ToolkitFeature.jobsWrite);

  /// Whether the toolkit lists what the agent did, which Activity shows.
  bool get activityServed => serves(ToolkitFeature.activity);

  /// Whether the bridge says where the suite's Library and Vault pages are, which the shelf's
  /// card shows a row for each of.
  bool get pagesServed => serves(ToolkitFeature.pages);

  final _pages = _Read<Set<SkillPage>>();

  /// Which of the suite's pages are set up, as the last read said; never where they are, since
  /// a page's address is a bearer capability that [pagePath] hands to its one caller.
  Set<SkillPage> get pagesFound => _pages.value ?? const {};

  final _jobs = _Read<List<ScheduledJob>>();
  final _activity = _Read<ActivityEvents>();

  /// The jobs the server runs on a schedule, or null until read.
  List<ScheduledJob>? get jobs => _jobs.value;

  /// Why the last read of the jobs failed.
  Notice? get jobsProblem => _jobs.problem;

  /// What the agent did, newest first, or null until read.
  List<ActivityEvent>? get activity => _activity.value?.events;

  /// Whether the toolkit has events older than [activity].
  bool get activityMore => _activity.value?.more ?? false;

  /// Why the last read of the activity failed.
  Notice? get activityProblem => _activity.problem;

  /// Whether events are being read.
  bool get activityLoading => _activity.pending != null;

  /// Whether a change to a job is on its way, which keeps a second from starting.
  bool busy = false;

  /// Why the last change failed, shown over what it changed until the next change, or until
  /// the jobs are read again, or [clearChangeProblem].
  Notice? changeProblem;

  /// The latest runs of each job read by [readRuns], by job id.
  final Map<String, List<JobRun>> runs = {};

  int _follows = 0;
  Timer? _watching;

  @override
  void serverChanged() {
    for (final read in [_jobs, _activity, _pages]) {
      read.reset();
    }
    busy = false;
    changeProblem = null;
    runs.clear();
    stopFollowing();
  }

  /// Whether a feature the toolkit serves has not been read on this server, nor is being read.
  bool get wants =>
      jobsServed && !_jobs.asked ||
      activityServed && !_activity.asked ||
      pagesServed && !_pages.asked;

  /// Reads each feature the toolkit serves that has not been read on this server, nor is being
  /// read.
  void want() {
    if (jobsServed && !_jobs.asked) unawaited(readJobs());
    if (activityServed && !_activity.asked) unawaited(readActivity());
    if (pagesServed && !_pages.asked) wantPages();
  }

  /// Reads which pages are set up afresh, unless that read is on its way. A refusal or any other
  /// failure leaves none found, and says nothing.
  void wantPages() => unawaited(
    _read(_pages, pagesServed, 'Could not read the pages', () async {
      try {
        return (await _api.pages()).keys.toSet();
      } on ApiException {
        return const <SkillPage>{};
      }
    }),
  );

  /// Where [page] is, read afresh and never kept, or null when it is not set up. The answer also
  /// says which pages are set up. A key the bridge refuses (401 or 403) leaves none found, and
  /// any [ApiException] is thrown on for the caller to show.
  Future<String?> pagePath(SkillPage page) async {
    final asked = epoch;
    try {
      final read = await _api.pages();
      if (asked != epoch) return null;
      _foundNow(read.keys.toSet());
      return read[page];
    } on ApiException catch (error) {
      if (asked == epoch && (error.status == 401 || error.status == 403)) {
        _foundNow(const {});
      }
      rethrow;
    }
  }

  /// Keeps [found] as the pages set up, telling the listeners only when that changed.
  void _foundNow(Set<SkillPage> found) {
    if (setEquals(_pages.value, found)) return;
    _pages.value = found;
    notifyListeners();
  }

  /// Reads the jobs the server runs on a schedule, or waits for the read on its way and, [again],
  /// reads afresh after it, for what a change made.
  Future<void> readJobs({bool again = false}) => _read(
    _jobs,
    jobsServed,
    'Could not read the scheduled jobs',
    _api.scheduledJobs,
    again: again,
    clearsChange: true,
  );

  /// Reads the newest events, in place of those read before, or waits for the read on its way.
  Future<void> readActivity() => _read(
    _activity,
    activityServed,
    'Could not read the activity',
    () => _api.activity(),
  );

  /// Reads the events before the oldest one read, and adds them.
  Future<void> moreActivity() async {
    final have = _activity.value;
    final before = have?.events.lastOrNull?.id;
    if (have == null || before == null || _activity.pending != null) return;
    await _read(
      _activity,
      activityServed,
      'Could not read the activity',
      () async {
        final older = await _api.activity(before: before);
        return ActivityEvents([
          ...have.events,
          ...older.events,
        ], more: older.more);
      },
    );
  }

  /// Reads [into] with [fetch] where the toolkit [served] it, showing why it failed as [title].
  /// While a read is on its way it waits for that one instead, and then reads afresh only
  /// [again]. A read that succeeds takes away the [changeProblem] when it [clearsChange].
  Future<void> _read<T>(
    _Read<T> into,
    bool served,
    String title,
    Future<T> Function() fetch, {
    bool again = false,
    bool clearsChange = false,
  }) async {
    if (!served) return;
    if (into.pending case final pending?) {
      await pending;
      if (!again) return;
    }
    final asked = epoch;
    final reading = into.pending = () async {
      try {
        final read = await fetch();
        if (asked != epoch) return;
        into
          ..value = read
          ..problem = null;
        if (clearsChange) changeProblem = null;
      } on ApiException catch (error) {
        if (asked != epoch) return;
        into.problem = Notice(title, error.message);
      } finally {
        // Another server's read, or a failure of any kind, leaves nothing marked as on its way.
        if (asked == epoch) {
          into.pending = null;
          notifyListeners();
        }
      }
    }();
    notifyListeners();
    await reading;
  }

  /// Reads job [id]'s latest runs, for the sheet that shows them.
  Future<void> readRuns(String id) async {
    final asked = epoch;
    try {
      final read = await _api.jobRuns(id);
      if (asked != epoch) return;
      runs[id] = read;
    } on ApiException {
      if (asked != epoch) return;
      runs.remove(id);
    }
    notifyListeners();
  }

  /// Makes the job [draft] says, or changes [existing] to it. Whether it went.
  Future<bool> saveJob(ScheduledJob? existing, JobDraft draft) {
    final id = existing?.id;
    return _change(
      id == null ? 'Could not add the task' : 'Could not save the task',
      () => id == null ? _api.createJob(draft) : _api.updateJob(id, draft),
    );
  }

  /// Switches job [id] on or off. Whether it went.
  Future<bool> setEnabled(String id, bool enabled) => _change(
    'Could not change the task',
    () => _api.setJobEnabled(id, enabled),
  );

  /// Deletes job [id]. Whether it went.
  Future<bool> removeJob(String id) =>
      _change('Could not delete the task', () => _api.deleteJob(id));

  /// Takes away the [changeProblem], as when the sheet that shows it closes.
  void clearChangeProblem() {
    if (changeProblem == null) return;
    changeProblem = null;
    notifyListeners();
  }

  /// Starts one run of job [id] now, then reads its runs, again every few seconds while it
  /// goes. Whether it started.
  Future<bool> runNow(String id) async {
    final started = await _change(
      'Could not start the task',
      () => _api.runJob(id),
    );
    if (started) await _follow(id, tries: 40);
    return started;
  }

  /// Reads [id]'s runs, and again in 3 seconds while its latest is still going, up to [tries]
  /// reads.
  Future<void> _follow(String id, {required int tries}) async {
    final asked = epoch;
    stopFollowing();
    final follow = _follows;
    await readRuns(id);
    // A stop while the runs were being read ends the following too.
    if (asked != epoch || follow != _follows || tries <= 1) return;
    if (runs[id]?.firstOrNull?.running ?? false) {
      _watching = Timer(const Duration(seconds: 3), () {
        unawaited(_follow(id, tries: tries - 1));
      });
    } else {
      // It ended: its last run and next time have changed.
      await readJobs(again: true);
    }
  }

  /// Stops reading a run's progress, as when its sheet closes.
  void stopFollowing() {
    _follows++;
    _watching?.cancel();
  }

  /// Sends [call], then reads the jobs again, whether it went or not, and shows why it failed
  /// over them. Whether it went.
  Future<bool> _change(String title, Future<void> Function() call) async {
    if (busy) return false;
    final asked = epoch;
    busy = true;
    changeProblem = null;
    notifyListeners();
    Notice? failed;
    try {
      await call();
    } on ApiException catch (error) {
      failed = Notice(title, error.message);
    } finally {
      // A failure of any other kind leaves the toolkit free for the next change too.
      if (asked == epoch) {
        busy = false;
        notifyListeners();
      }
    }
    if (asked != epoch) return false;
    await readJobs(again: true);
    if (failed != null) {
      changeProblem = failed;
      notifyListeners();
    }
    return failed == null;
  }

  @override
  void dispose() {
    stopFollowing();
    unwatch();
    super.dispose();
  }
}

/// One list the toolkit serves: what was read last, why the last read failed, and the read on
/// its way.
class _Read<T> {
  T? value;
  Notice? problem;
  Future<void>? pending;

  /// Whether it was read, refused, or is being read.
  bool get asked => value != null || problem != null || pending != null;

  void reset() {
    value = null;
    problem = null;
    pending = null;
  }
}
