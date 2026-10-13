import 'package:flutter/foundation.dart';

import '../../core/ports.dart';
import '../../core/schedule.dart';
import '../../core/toolkit.dart';
import 'companion_watch.dart';
import 'notice.dart';
import 'settings_controller.dart';

/// What the app knows of the toolkit beside the server in use: whether it is there, what it
/// serves, and the scheduled jobs it lists. Another server starts it afresh, and Test
/// connection asks again whether the toolkit is there.
class ToolkitController extends ChangeNotifier with CompanionWatch {
  ToolkitController(this._api, SettingsController settings) {
    watch(_api, settings);
  }

  final ToolkitApi _api;

  /// Whether the toolkit serves the saved memories, which the Memory page shows.
  bool get memories => serves(ToolkitFeature.memories);

  /// Whether the toolkit lists the scheduled jobs, which Upcoming shows.
  bool get jobsServed => serves(ToolkitFeature.jobs);

  /// The jobs the server runs on a schedule, or null until read.
  List<ScheduledJob>? jobs;

  /// Why the last read of the jobs failed.
  Notice? jobsProblem;

  @override
  void serverChanged() {
    jobs = null;
    jobsProblem = null;
  }

  /// Reads the jobs the server runs on a schedule.
  Future<void> readJobs() async {
    final asked = epoch;
    if (!jobsServed) return;
    try {
      final read = await _api.scheduledJobs();
      if (asked != epoch) return;
      jobs = read;
      jobsProblem = null;
    } on ApiException catch (error) {
      if (asked != epoch) return;
      jobsProblem = Notice('Could not read the scheduled jobs', error.message);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unwatch();
    super.dispose();
  }
}
