import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/activity.dart';
import '../../core/asks.dart';
import '../../core/library.dart';
import '../../core/ports.dart';
import '../../core/schedule.dart';
import '../../core/toolkit.dart';
import 'companion_watch.dart';
import 'notice.dart';
import 'settings_controller.dart';

/// What the app knows of the toolkit beside the server in use: whether it is there, what its
/// bridge lets through, the scheduled jobs, which, where it allows, the app makes, changes,
/// runs and deletes, and the hosts its skills may always reach.
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

  /// Whether the toolkit lists the apps and files the agent made, which Library shows.
  bool get libraryServed => serves(ToolkitFeature.library);

  /// Whether the toolkit lists what the agent did, which Activity shows.
  bool get activityServed => serves(ToolkitFeature.activity);

  /// Whether the toolkit's skills ask the person here, which Allowed hosts goes with.
  bool get asksServed => serves(ToolkitFeature.asks);

  final _jobs = _Read<List<ScheduledJob>>();
  final _library = _Read<LibraryContents>();
  final _activity = _Read<ActivityEvents>();
  final _allowed = _Read<List<AllowedHost>>();

  /// The jobs the server runs on a schedule, or null until read.
  List<ScheduledJob>? get jobs => _jobs.value;

  /// Why the last read of the jobs failed.
  Notice? get jobsProblem => _jobs.problem;

  /// The apps and files the agent made, or null until read.
  LibraryContents? get library => _library.value;

  /// Why the last read of the Library failed.
  Notice? get libraryProblem => _library.problem;

  /// What the agent did, newest first, or null until read.
  List<ActivityEvent>? get activity => _activity.value?.events;

  /// Whether the toolkit has events older than [activity].
  bool get activityMore => _activity.value?.more ?? false;

  /// Why the last read of the activity failed.
  Notice? get activityProblem => _activity.problem;

  /// Whether events are being read.
  bool get activityLoading => _activity.pending != null;

  /// The hosts skills may always reach, or null until read.
  List<AllowedHost>? get allowed => _allowed.value;

  /// Why the last read of the allowed hosts failed.
  Notice? get allowedProblem => _allowed.problem;

  /// Whether the allowed hosts are being read.
  bool get allowedLoading => _allowed.pending != null;

  /// Whether a change to a job or an allowed host is on its way, which keeps a second from
  /// starting.
  bool busy = false;

  /// Why the last change failed, shown over what it changed until the next change.
  Notice? changeProblem;

  /// The latest runs of each job read by [readRuns], by job id.
  final Map<String, List<JobRun>> runs = {};

  int _follows = 0;
  Timer? _watching;

  @override
  void serverChanged() {
    for (final read in [_jobs, _library, _activity, _allowed]) {
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
      libraryServed && !_library.asked ||
      activityServed && !_activity.asked;

  /// Reads each feature the toolkit serves that has not been read on this server, nor is being
  /// read.
  void want() {
    if (jobsServed && !_jobs.asked) unawaited(readJobs());
    if (libraryServed && !_library.asked) unawaited(readLibrary());
    if (activityServed && !_activity.asked) unawaited(readActivity());
  }

  /// Reads the jobs the server runs on a schedule, or waits for the read on its way and, [again],
  /// reads afresh after it, for what a change made.
  Future<void> readJobs({bool again = false}) => _read(
    _jobs,
    jobsServed,
    'Could not read the scheduled jobs',
    _api.scheduledJobs,
    again: again,
  );

  /// Reads the apps and files the agent made, or waits for the read on its way.
  Future<void> readLibrary() => _read(
    _library,
    libraryServed,
    'Could not read the Library',
    _api.library,
  );

  /// Reads the hosts skills may always reach, or waits for the read on its way and, [again],
  /// reads afresh after it.
  Future<void> readAllowed({bool again = false}) => _read(
    _allowed,
    asksServed,
    'Could not read the allowed hosts',
    _api.allowedHosts,
    again: again,
  );

  /// Reads the allowed hosts after the frame, when the toolkit serves them and they are not read
  /// yet, so a page may ask while it builds.
  void wantAllowed() {
    if (!asksServed || _allowed.asked) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_allowed.asked) unawaited(readAllowed());
    });
  }

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
  /// [again].
  Future<void> _read<T>(
    _Read<T> into,
    bool served,
    String title,
    Future<T> Function() fetch, {
    bool again = false,
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
      } on ApiException catch (error) {
        if (asked != epoch) return;
        into.problem = Notice(title, error.message);
      }
      into.pending = null;
      notifyListeners();
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

  /// Stops always allowing [host], then reads the allowed hosts again.
  Future<void> forgetHost(String host) => _change(
    'Could not remove $host',
    () => _api.forgetHost(host),
    readAgain: () => readAllowed(again: true),
  );

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

  /// Sends [call], then reads what it changed again ([readAgain], else the jobs), whether it
  /// went or not, and shows why it failed over them. Whether it went.
  Future<bool> _change(
    String title,
    Future<void> Function() call, {
    Future<void> Function()? readAgain,
  }) async {
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
    }
    if (asked != epoch) return false;
    busy = false;
    await (readAgain ?? () => readJobs(again: true))();
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
