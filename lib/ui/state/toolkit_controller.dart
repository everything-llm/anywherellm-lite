import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../../core/browser_tabs.dart';
import '../../core/connection.dart';
import '../../core/page_status.dart';
import '../../core/ports.dart';
import '../../core/schedule.dart';
import '../../core/skill_pages.dart';
import '../../core/toolkit.dart';
import 'follows_server.dart';
import 'notice.dart';
import 'read.dart';
import 'settings_controller.dart';

/// What the app knows of the toolkit beside the server in use: whether it is there
/// ([available]), what its bridge lets through, the pages set up and the scheduled jobs, which,
/// where it allows, the app makes, changes, runs and deletes. Another server, or the toolkit said
/// to run elsewhere, starts it afresh, Test connection asks again whether the toolkit is there,
/// and an answer from before either is dropped, even once the server is back.
class ToolkitController extends ChangeNotifier with FollowsServer {
  ToolkitController(this._api, this._settings, {required this._tabState}) {
    followServer(_settings);
    _tests = _settings.tests;
    _settings.addListener(_tested);
    if (server != null) unawaited(_detect());
  }

  final ToolkitApi _api;
  final SettingsController _settings;

  /// What browser-lean wrote about the tab whose page is at a path ([AnythingLlmApi.tabState]).
  final Future<TabState> Function(String path) _tabState;

  /// How many times Test connection had asked, as last seen.
  int _tests = 0;

  /// The server in use and where the toolkit was said to run beside it: another of either starts
  /// this afresh.
  @override
  Object? get serverKey =>
      (_settings.connection, _settings.addressOf(toolkitCompanion));

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

  late final _pages = ReadSlot<_PagesRead>(notifyListeners);

  /// Which of the suite's pages are set up, as the last read said; never where they are, since
  /// a page's address is a bearer capability that [pagePath] hands to its one caller.
  Set<SkillPage> get pagesFound => _pages.value?.found ?? const {};

  /// The agent's browser's tabs still open now, as the last read of the pages listed them, or
  /// null when the toolkit does not serve the pages or the bridge does not say. Their paths are
  /// held in memory only.
  List<OpenTab>? get tabs {
    final listed = _pages.value?.rest.tabs;
    return pagesServed && listed != null
        ? stillOpen(listed, clock.now())
        : null;
  }

  /// What the last read of the pages said of them.
  PageStatus get pageStatus => _pages.value?.rest.status ?? const PageStatus();

  /// What browser-lean last wrote about each tab [readTabs] read, by its page's path.
  Map<String, TabState> _tabStates = const {};

  /// The tabs whose state the last [readTabs] could not read.
  Set<String> _tabsFailed = const {};

  /// How many times [readTabs] began, so only the newest keeps its answer.
  int _tabReads = 0;

  /// The state of the tab at [path], or null until [readTabs] read it.
  TabState? tabState(String path) => _tabStates[path];

  /// Whether the last read of the tab at [path] failed.
  bool tabFailed(String path) => _tabsFailed.contains(path);

  late final _jobs = ReadSlot<List<ScheduledJob>>(notifyListeners);

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
  /// from the one before and asks afresh.
  @override
  void serverChanged(Connection? was) {
    _tests = _settings.tests;
    available = null;
    _features = const {};
    _jobs.reset();
    _pages.reset();
    _tabStates = const {};
    _tabsFailed = const {};
    _tabReads++;
    busy = false;
    changeProblem = null;
    runs.clear();
    stopFollowing();
    notifyListeners();
    // The same server with the toolkit said to run elsewhere asks there afresh.
    if (server != null) unawaited(_detect(again: server == was));
  }

  /// Test connection asks again where the toolkit is.
  void _tested() {
    if (_settings.tests == _tests) return;
    _tests = _settings.tests;
    if (server != null) unawaited(_detect(again: true));
  }

  /// Asks whether the toolkit is there and what it serves, [again] afresh.
  Future<void> _detect({bool again = false}) async {
    final at = here;
    final found = await _api.features(again: again);
    if (!at.unchanged) return;
    final features = found ?? const <String>{};
    if (available == (found != null) && setEquals(features, _features)) return;
    available = found != null;
    _features = features;
    notifyListeners();
  }

  /// Reads the jobs after the frame, where the toolkit serves them and they have not been read
  /// on this server, nor are being read, as the Settings list does for Upcoming's line.
  void wantJobsOnce() {
    if (!jobsServed || _jobs.asked) return;
    afterFrame(() {
      if (!_jobs.asked) unawaited(readJobs());
    });
  }

  /// Reads which pages are set up after the frame, where the toolkit serves them and they have
  /// not been read on this server, nor are being read, as the shelf's card does once the
  /// toolkit is found.
  void wantPagesOnce() {
    if (!pagesServed || _pages.asked) return;
    afterFrame(() {
      if (!_pages.asked) _readPages();
    });
  }

  /// Reads which pages are set up afresh, after the frame, unless that read is on its way.
  void wantPages() => afterFrame(_readPages);

  /// Reads which pages are set up afresh unless that read is on its way.
  void _readPages() => unawaited(readPages());

  /// Reads which pages are set up afresh, or waits for the read on its way. A refusal or any
  /// other failure leaves none found and no tabs, and says nothing.
  Future<void> readPages() async {
    if (!pagesServed) return;
    await _pages.read(
      () async {
        try {
          return _kept(await _api.pages());
        } on ApiException {
          return _nothingFound;
        }
      },
      failTitle: 'Could not read the pages',
      join: true,
    );
  }

  /// Where [page] is, read afresh and never kept, or null when it is not set up. The answer also
  /// says which pages are set up. A key the bridge refuses (401 or 403) leaves none found, and
  /// any [ApiException] is thrown on for the caller to show.
  Future<String?> pagePath(SkillPage page) async {
    final at = here;
    try {
      final read = await _api.pages();
      if (!at.unchanged) return null;
      _foundNow(_kept(read));
      return read.paths[page];
    } on ApiException catch (error) {
      if (at.unchanged && (error.status == 401 || error.status == 403)) {
        _foundNow(_nothingFound);
      }
      rethrow;
    }
  }

  /// Reads the pages afresh, then the state of each tab they list, at once, telling the
  /// listeners once they are all back. A tab whose state cannot be read is [tabFailed].
  Future<void> readTabs() async {
    await readPages();
    final at = here;
    final read = ++_tabReads;
    final paths = [for (final tab in tabs ?? const <OpenTab>[]) tab.path];
    final states = await Future.wait([
      for (final path in paths) _tabStateOrNull(path),
    ]);
    if (!at.unchanged || read != _tabReads) return;
    _tabStates = {for (final (i, path) in paths.indexed) path: ?states[i]};
    _tabsFailed = {
      for (final (i, path) in paths.indexed)
        if (states[i] == null) path,
    };
    notifyListeners();
  }

  /// The state of the tab at [path], or null when it cannot be read.
  Future<TabState?> _tabStateOrNull(String path) async {
    try {
      return await _tabState(path);
    } on ApiException {
      return null;
    }
  }

  /// Keeps [read] as what the pages last said.
  void _foundNow(_PagesRead read) {
    _pages.value = read;
    notifyListeners();
  }

  /// Reads the jobs afresh after the frame, unless that read is on its way, as Upcoming does as
  /// it opens.
  void wantJobs() => afterFrame(() => unawaited(readJobs()));

  /// Reads the jobs the server runs on a schedule, or waits for the read on its way and, [again],
  /// reads afresh after it, for what a change made. A read that succeeds takes away the
  /// [changeProblem].
  Future<void> readJobs({bool again = false}) async {
    if (!jobsServed) return;
    await _jobs.read(
      _api.scheduledJobs,
      failTitle: 'Could not read the scheduled jobs',
      kept: (_) => changeProblem = null,
      join: true,
      again: again,
    );
  }

  /// Reads job [id]'s latest runs, for the sheet that shows them.
  Future<void> readRuns(String id) async {
    final at = here;
    try {
      final read = await _api.jobRuns(id);
      if (!at.unchanged) return;
      runs[id] = read;
    } on ApiException {
      if (!at.unchanged) return;
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
    if (started) await follow(id, started: true);
    return started;
  }

  /// Reads job [id]'s runs, and again every 3 seconds while its latest is still going, up to 40
  /// reads, so a run is followed to its end; the jobs are read again once it ends, since its
  /// last run and next time have changed. A run the first read finds ended already changed them
  /// only when it was just [started]. Following another run, or [stopFollowing], ends it.
  Future<void> follow(String id, {bool started = false}) =>
      _follow(id, tries: 40, first: !started);

  /// One read of [follow], with [tries] reads left; the [first] read of a run not just started
  /// leaves the jobs as they are.
  Future<void> _follow(
    String id, {
    required int tries,
    bool first = false,
  }) async {
    final at = here;
    stopFollowing();
    final following = _follows;
    await readRuns(id);
    // A stop while the runs were being read ends the following too.
    if (!at.unchanged || following != _follows) return;
    if (runs[id]?.firstOrNull?.running ?? false) {
      if (tries > 1) {
        _watching = Timer(const Duration(seconds: 3), () {
          unawaited(_follow(id, tries: tries - 1));
        });
      }
    } else if (!first) {
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
    final at = here;
    changeProblem = null;
    return changeThenRead(
      title,
      call,
      current: () => at.unchanged,
      busy: (on) {
        busy = on;
        notifyListeners();
      },
      readAgain: (failed) async {
        await readJobs(again: true);
        if (failed != null) {
          changeProblem = failed;
          notifyListeners();
        }
      },
    );
  }

  @override
  void dispose() {
    stopFollowing();
    _settings.removeListener(_tested);
    super.dispose();
  }
}

/// What a read of the pages keeps: which are set up, never where, and the rest of what it
/// said with no paths.
typedef _PagesRead = ({Set<SkillPage> found, SuitePages rest});

/// What [read] keeps.
_PagesRead _kept(SuitePages read) => (
  found: read.paths.keys.toSet(),
  rest: SuitePages(tabs: read.tabs, status: read.status),
);

/// Nothing set up, as a refusal leaves it.
const _PagesRead _nothingFound = (found: <SkillPage>{}, rest: SuitePages());
