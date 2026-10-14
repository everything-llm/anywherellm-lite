import 'copy.dart';
import 'json.dart';
import 'server_models.dart' show jsonObjects;

/// What a run's or a job's latest status word means: true for one the server calls completed,
/// false for one it calls failed, and null for any other word, such as one still running.
bool? _wentWell(String? status) => switch (status?.toLowerCase()) {
  'completed' || 'complete' || 'done' || 'success' || 'succeeded' => true,
  'failed' || 'failure' || 'error' || 'errored' => false,
  _ => null,
};

/// A job AnythingLLM runs on a schedule: its [id] when the toolkit gives one, its [name], what
/// it asks ([prompt]) or the saved [action] it runs instead, the [workspace] it runs in when the
/// server says (and its [workspaceSlug]), its [cron] schedule in UTC, whether it is [enabled],
/// when it runs next and last, and how its latest run went.
class ScheduledJob {
  const ScheduledJob({
    required this.name,
    required this.cron,
    this.id,
    this.prompt = '',
    this.action,
    this.workspace,
    this.workspaceSlug,
    this.enabled = true,
    this.nextRun,
    this.lastRun,
    this.lastStatus,
  });

  /// A job as `/api/scheduled-jobs` lists it, or null without a name. The workspace may be a
  /// slug, an object with a name, or a `workspaceSlug`; a time is ISO 8601 text.
  static ScheduledJob? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;
    final latest = json['latestRun'];
    final named = json['workspaceSlug'];
    return ScheduledJob(
      id: idOrNull(json['id']),
      name: name,
      cron: json['schedule'] is String ? json['schedule'] as String : '',
      prompt: json['prompt'] is String ? json['prompt'] as String : '',
      action: textOrNull(json['runAction']),
      workspace: switch (json['workspace']) {
        {'name': final String name} => name,
        final String slug => slug,
        _ => named is String ? named : null,
      },
      workspaceSlug: switch (json['workspace']) {
        {'slug': final String slug} => slug,
        final String slug => slug,
        _ => named is String ? named : null,
      },
      enabled: json['enabled'] != false,
      nextRun: timeOrNull(json['nextRunAt']),
      lastRun:
          timeOrNull(json['lastRunAt']) ??
          (latest is Map ? timeOrNull(latest['startedAt']) : null),
      lastStatus: latest is Map && latest['status'] is String
          ? latest['status'] as String
          : null,
    );
  }

  /// The toolkit's id for the job, which changing, running or deleting it needs; null from a
  /// toolkit that gives none, which leaves the job read only.
  final String? id;
  final String name;

  /// What the job asks, empty for one that runs a saved [action].
  final String prompt;

  /// The title of the saved action the job runs in place of a prompt, or null.
  final String? action;
  final String? workspace;
  final String? workspaceSlug;
  final String cron;
  final bool enabled;
  final DateTime? nextRun;
  final DateTime? lastRun;

  /// How the latest run ended, in the server's word, such as `completed` or `failed`.
  final String? lastStatus;

  /// Whether the latest run went well: true for one the server calls completed, false for one
  /// it calls failed, and null for any other word, such as one still running, or none.
  bool? get lastWentWell => _wentWell(lastStatus);
}

/// One run of a [ScheduledJob]: when it started, the server's word for how it [status] ended and
/// the [result] it left.
class JobRun {
  const JobRun({this.startedAt, this.status, this.result});

  /// A run as the toolkit lists it.
  static JobRun fromJson(Map<String, dynamic> json) => JobRun(
    startedAt: timeOrNull(json['startedAt']),
    status: json['status'] is String ? json['status'] as String : null,
    result: json['result'] is String ? json['result'] as String : null,
  );

  final DateTime? startedAt;
  final String? status;
  final String? result;

  /// Whether the run ended well (true), failed (false), or has not ended (null).
  bool? get wentWell => _wentWell(status);

  /// Whether the run is still going.
  bool get running => const {
    'running',
    'started',
    'pending',
    'queued',
  }.contains(status?.toLowerCase());
}

/// The runs in a toolkit's answer: a list, or an object with them under `runs`.
List<JobRun> jobRunsOf(Object? json) => [
  for (final run in jsonObjects(json is Map ? json['runs'] : json))
    JobRun.fromJson(run),
];

/// What a new or changed job says: the fields the toolkit takes. [cron] is in UTC. A [once] job
/// is switched off by the toolkit after it runs.
class JobDraft {
  const JobDraft({
    required this.name,
    required this.prompt,
    required this.workspaceSlug,
    required this.cron,
    this.once = false,
    this.enabled = true,
  });

  final String name;
  final String prompt;
  final String workspaceSlug;
  final String cron;
  final bool once;
  final bool enabled;

  Map<String, Object?> toJson() => {
    'name': name,
    'prompt': prompt,
    'workspace': workspaceSlug,
    'schedule': cron,
    'once': once,
    'enabled': enabled,
  };
}

/// The jobs in a `/api/scheduled-jobs` answer: a list, or an object with them under `jobs`.
List<ScheduledJob> scheduledJobsOf(Object? json) => [
  for (final job in jsonObjects(json is Map ? json['jobs'] : json))
    ?ScheduledJob.fromJson(job),
];

/// The N of a `*/N` cron field, which runs every N minutes or hours, or null for another field.
int? cronStep(String field) =>
    switch (RegExp(r'^\*/(\d+)$').firstMatch(field)) {
      final every? => int.parse(every.group(1)!),
      null => null,
    };

/// [at]'s date as a short day, the day of the month and the month: `Mon 6 Oct`.
String dateText(DateTime at) =>
    '${_shortDay(at.weekday - 1)} ${at.day} ${monthNames[at.month - 1]}';

/// The weekday at [index], Monday 0, as three letters: `Mon`.
String _shortDay(int index) => weekdayNames[index].substring(0, 3);

/// [cron], which runs in UTC, in plain words in local time, as [now] gives it: every few
/// minutes, every hour, every day, every weekday or one day a week. Any other schedule is the
/// cron itself, marked UTC.
String describeSchedule(String cron, DateTime now) {
  final parts = cron.trim().split(RegExp(r'\s+'));
  if (parts.length != 5) return cron.isEmpty ? 'No schedule' : '$cron (UTC)';
  final [minute, hour, day, month, weekday] = parts;
  if (day != '*' || month != '*') return '$cron (UTC)';
  if (cronStep(minute) case final n? when hour == '*' && weekday == '*') {
    return n == 1 ? 'Every minute' : 'Every ${plural(n, 'minute', 'minutes')}';
  }
  final m = int.tryParse(minute);
  if (m == null || m > 59) return '$cron (UTC)';
  if (hour == '*' && weekday == '*') {
    return 'Every hour at :${m.toString().padLeft(2, '0')}';
  }
  // Every few hours, which a time zone a whole number of hours away leaves as it is.
  if (cronStep(hour) case final n? when weekday == '*' && m == 0) {
    return n == 1 ? 'Every hour' : 'Every ${plural(n, 'hour', 'hours')}';
  }
  final h = int.tryParse(hour);
  if (h == null || h > 23) return '$cron (UTC)';
  final utcNow = now.toUtc();
  // The time in local time, and how many days that moves the day.
  final at = DateTime.utc(utcNow.year, utcNow.month, utcNow.day, h, m);
  final local = at.toLocal();
  // Compared as UTC dates, so a clock change between the two days cannot make a day 23 hours.
  final shift = DateTime.utc(
    local.year,
    local.month,
    local.day,
  ).difference(DateTime.utc(at.year, at.month, at.day)).inDays;
  final time = clockText(local);
  switch (weekday) {
    case '*':
      return 'Every day at $time';
    case '1-5' when shift == 0:
      return 'Weekdays at $time';
  }
  final d = int.tryParse(weekday);
  if (d == null || d > 7) return '$cron (UTC)';
  // Cron counts Sunday as 0 or 7; the list starts on Monday.
  final monday0 = (d + 6) % 7;
  return 'Every ${_shortDay((monday0 + shift) % 7)} at $time';
}

/// When [at] is, in local time, from [now]: today or tomorrow at a time, or a date and time.
String whenText(DateTime at, DateTime now) {
  final local = at.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = day.difference(today).inDays;
  final time = clockText(local);
  return switch (days) {
    0 => 'today $time',
    1 => 'tomorrow $time',
    -1 => 'yesterday $time',
    _ => '${dateText(local)}, $time',
  };
}

/// The day [at] falls on, in local time, as [now] gives it: Today, Yesterday, or `Mon 6 Oct`.
String dayText(DateTime at, DateTime now) {
  final local = at.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final days = DateTime(
    local.year,
    local.month,
    local.day,
  ).difference(today).inDays;
  return switch (days) {
    0 => 'Today',
    -1 => 'Yesterday',
    _ => dateText(local),
  };
}
