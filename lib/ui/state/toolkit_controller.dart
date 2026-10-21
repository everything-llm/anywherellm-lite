import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/connection.dart';
import '../../core/ports.dart';
import '../../core/schedule.dart';
import '../../core/skill_pages.dart';
import '../../core/toolkit.dart';
import 'notice.dart';
import 'settings_controller.dart';

/// What the app knows of the toolkit beside the server in use: whether it is there
/// ([available]), what its bridge lets through, the pages set up and the scheduled jobs, which,
/// where it allows, the app makes, changes, runs and deletes. Another server, or the toolkit said
/// to run elsewhere, starts it afresh, Test connection asks again whether the toolkit is there,
/// and an answer about a server no longer in use is dropped.
class ToolkitController extends ChangeNotifier {
  ToolkitController(this._api, this._settings) {
    _server = _settings.connection;
    _address = _settings.addressOf(toolkitCompanion);
    _tests = _settings.tests;
    _settings.addListener(_settingsChanged);
    if (_server != null) unawaited(_detect());
  }

  final ToolkitApi _api;
  final SettingsController _settings;

  /// The server in use, and where the toolkit was said to run beside it, as last seen.
  Connection? _server;
  Uri? _address;
  int _tests = 0;

  /// Counts the connection changes, so an answer from the server before is dropped.
  int _epoch = 0;

  /// Whether the toolkit answers beside the server in use: null until it is asked.
  bool? available;
  Set<String> _features = const {};

  /// Whether the toolkit's `/health` names [feature].
  bool _serves(String feature) => _features.contains(feature);

  /// Whether the toolkit is known to serve nothing: it is not there, or names no feature.
  bool get servesNothing => available != null && _features.isEmpty;

  /// Whether the toolkit serves the saved memories, which the Memory page shows.
  bool get memories => _serves(ToolkitFeature.memories);

  /// Whether the toolkit lists the scheduled jobs, which Upcoming shows.
  bool get jobsServed => _serves(ToolkitFeature.jobs);

  /// Whether the toolkit lets jobs be made, changed, run and deleted, not only listed.
  bool get jobsWritable => _serves(ToolkitFeature.jobsWrite);

  /// Whether the bridge says where the suite's Library and Vault pages are, which the shelf's
  /// card shows a row for each of.
  bool get pagesServed => _serves(ToolkitFeature.pages);

  final _pages = _Read<Set<SkillPage>>();

  /// Which of the suite's pages are set up, as the last read said; never where they are, since
  /// a page's address is a bearer capability that [pagePath] hands to its one caller.
  Set<SkillPage> get pagesFound => _pages.value ?? const {};

  final _jobs = _Read<List<ScheduledJob>>();

  /// The jobs the server runs on a schedule, or null until read.
  List<ScheduledJob>? get jobs => _jobs.value;

  /// Why the last read of the jobs failed.
  Notice? get jobsProblem => _jobs.problem;

  /// Whether a change to a job is on its way, which keeps a second from starting.
  bool busy = false;

  /// Why the last change failed, shown over what it changed until the next change, or until
  /// the jobs are read again, or [clearChangeProblem].
  Notice? changeProblem;

  /// The latest runs of each job read by [readRuns], by job id.
  final Map<String, List<JobRun>> runs = {};

  int _follows = 0;
  Timer? _watching;

  /// Another server is in use, or the toolkit was said to run elsewhere: forgets what was read
  /// from the one before and asks afresh. Test connection asks again where it is.
  void _settingsChanged() {
    final here = _settings.connection;
    final address = _settings.addressOf(toolkitCompanion);
    if (here != _server || address != _address) {
      // The same server with the toolkit said to run elsewhere asks there afresh.
      final moved = here == _server;
      _server = here;
      _address = address;
      _tests = _settings.tests;
      _epoch++;
      available = null;
      _features = const {};
      for (final read in [_jobs, _pages]) {
        read.reset();
      }
      busy = false;
      changeProblem = null;
      runs.clear();
      stopFollowing();
      notifyListeners();
      if (here != null) unawaited(_detect(again: moved));
      return;
    }
    if (_settings.tests != _tests) {
      _tests = _settings.tests;
      if (here != null) unawaited(_detect(again: true));
    }
  }

  /// Asks whether the toolkit is there and what it serves, [again] afresh.
  Future<void> _detect({bool again = false}) async {
    final asked = _epoch;
    final found = await _api.features(again: again);
    if (asked != _epoch) return;
    final features = found ?? const <String>{};
    if (available == (found != null) && setEquals(features, _features)) return;
    available = found != null;
    _features = features;
    notifyListeners();
  }

  /// Whether a feature the toolkit serves has not been read on this server, nor is being read.
  bool get wants => jobsServed && !_jobs.asked || pagesServed && !_pages.asked;

  /// Reads each feature the toolkit serves that has not been read on this server, nor is being
  /// read.
  void want() {
    if (jobsServed && !_jobs.asked) unawaited(readJobs());
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
    final asked = _epoch;
    try {
      final read = await _api.pages();
      if (asked != _epoch) return null;
      _foundNow(read.keys.toSet());
      return read[page];
    } on ApiException catch (error) {
      if (asked == _epoch && (error.status == 401 || error.status == 403)) {
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
    final asked = _epoch;
    final reading = into.pending = () async {
      try {
        final read = await fetch();
        if (asked != _epoch) return;
        into
          ..value = read
          ..problem = null;
        if (clearsChange) changeProblem = null;
      } on ApiException catch (error) {
        if (asked != _epoch) return;
        into.problem = Notice(title, error.message);
      } finally {
        // Another server's read, or a failure of any kind, leaves nothing marked as on its way.
        if (asked == _epoch) {
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
    final asked = _epoch;
    try {
      final read = await _api.jobRuns(id);
      if (asked != _epoch) return;
      runs[id] = read;
    } on ApiException {
      if (asked != _epoch) return;
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
    final asked = _epoch;
    stopFollowing();
    final follow = _follows;
    await readRuns(id);
    // A stop while the runs were being read ends the following too.
    if (asked != _epoch || follow != _follows || tries <= 1) return;
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
    final asked = _epoch;
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
      if (asked == _epoch) {
        busy = false;
        notifyListeners();
      }
    }
    if (asked != _epoch) return false;
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
    _settings.removeListener(_settingsChanged);
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
