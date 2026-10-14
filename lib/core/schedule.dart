import 'copy.dart';
import 'json.dart';
import 'server_models.dart' show jsonObjects;

/// What a run's or a job's latest status word means: true for one the server calls completed,
/// false for one it calls failed or timed out, and null for any other word, such as one still
/// running.
bool? _wentWell(String? status) => switch (status?.toLowerCase()) {
  'completed' || 'complete' || 'done' || 'success' || 'succeeded' => true,
  'failed' || 'failure' || 'error' || 'errored' || 'timed_out' => false,
  _ => null,
};

/// A job AnythingLLM runs on a schedule: its [id], its [name], what it asks ([prompt]), how many
/// [tools] it may use, its [cron] schedule in UTC, whether it is [enabled], when it runs next and
/// last, and how its latest run went.
class ScheduledJob {
  const ScheduledJob({
    required this.name,
    required this.cron,
    this.id,
    this.prompt = '',
    this.tools = 0,
    this.enabled = true,
    this.nextRun,
    this.lastRun,
    this.lastStatus,
  });

  /// A job as `/api/scheduled-jobs` lists it, or null without a name. Its `tools` are a list, or
  /// JSON text holding one; a time is ISO 8601 text.
  static ScheduledJob? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;
    final latest = json['latestRun'];
    return ScheduledJob(
      id: idOrNull(json['id']),
      name: name,
      cron: json['schedule'] is String ? json['schedule'] as String : '',
      prompt: json['prompt'] is String ? json['prompt'] as String : '',
      tools: switch (jsonOrSelf(json['tools'])) {
        final List<dynamic> tools => tools.length,
        _ => 0,
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

  /// AnythingLLM's id for the job, which changing, running or deleting it needs; null from a
  /// server that gives none, which leaves the job read only.
  final String? id;
  final String name;

  /// What the job asks.
  final String prompt;

  /// How many tools the job may use, which only AnythingLLM's web page sets.
  final int tools;
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
/// the [result] it left: its answer, or why it failed.
class JobRun {
  const JobRun({this.startedAt, this.status, this.result});

  /// A run as `/api/scheduled-jobs/<id>/runs` lists it: its `result` JSON text holding the
  /// answer's `text`, and an `error` for one that failed.
  static JobRun fromJson(Map<String, dynamic> json) {
    final status = json['status'] is String ? json['status'] as String : null;
    final text = switch (jsonOrSelf(json['result'])) {
      {'text': final String text} => text,
      final String text => text,
      _ => null,
    };
    final error = textOrNull(json['error']);
    return JobRun(
      startedAt: timeOrNull(json['startedAt']),
      status: status,
      result: (_wentWell(status) == false ? error ?? text : text ?? error)
          ?.trim(),
    );
  }

  final DateTime? startedAt;
  final String? status;
  final String? result;

  /// Whether the run ended well (true), failed (false), or has not ended (null).
  bool? get wentWell => _wentWell(status);

  /// Whether the run is still going, or waits its turn.
  bool get running => const {
    'running',
    'started',
    'pending',
    'queued',
  }.contains(status?.toLowerCase());
}

/// The first [limit] runs in an answer, a list or an object with them under `runs`, each read
/// only when kept, since a run's result can be a long trace.
List<JobRun> jobRunsOf(Object? json, {int? limit}) {
  final runs = jsonObjects(json is Map ? json['runs'] : json);
  return [
    for (final run in limit == null ? runs : runs.take(limit))
      JobRun.fromJson(run),
  ];
}

/// What a new or changed job says, as AnythingLLM takes it. [cron] is in UTC. Its tools are left
/// as they are: none for a new job.
class JobDraft {
  const JobDraft({
    required this.name,
    required this.prompt,
    required this.cron,
  });

  final String name;
  final String prompt;
  final String cron;

  Map<String, Object?> toJson() => {
    'name': name,
    'prompt': prompt,
    'schedule': cron,
  };
}

/// The jobs in a `/api/scheduled-jobs` answer: a list, or an object with them under `jobs`.
List<ScheduledJob> scheduledJobsOf(Object? json) => [
  for (final job in jsonObjects(json is Map ? json['jobs'] : json))
    ?ScheduledJob.fromJson(job),
];

/// The N of a `*/N` cron field, which runs every N minutes or hours, or null for another field.
int? _cronStep(String field) =>
    switch (RegExp(r'^\*/(\d+)$').firstMatch(field)) {
      final every? => int.parse(every.group(1)!),
      null => null,
    };

/// [at]'s date as a short day, the day of the month and the month: `Mon 6 Oct`.
String _dateText(DateTime at) =>
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
  if (_cronStep(minute) case final n? when hour == '*' && weekday == '*') {
    return n == 1 ? 'Every minute' : 'Every ${plural(n, 'minute', 'minutes')}';
  }
  final m = int.tryParse(minute);
  if (m == null || m > 59) return '$cron (UTC)';
  if (hour == '*' && weekday == '*') {
    return 'Every hour at :${m.toString().padLeft(2, '0')}';
  }
  // Every few hours, which a time zone a whole number of hours away leaves as it is.
  if (_cronStep(hour) case final n? when weekday == '*' && m == 0) {
    return n == 1 ? 'Every hour' : 'Every ${plural(n, 'hour', 'hours')}';
  }
  final h = int.tryParse(hour);
  if (h == null || h > 23) return '$cron (UTC)';
  final utcNow = now.toUtc();
  // The time in local time, and how many days that moves the day.
  final at = DateTime.utc(utcNow.year, utcNow.month, utcNow.day, h, m);
  final local = at.toLocal();
  final shift = calendarDays(local, at);
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

/// The calendar days from [from]'s date to [local]'s, compared as UTC dates so a clock change
/// between them cannot make a day 23 hours and round to none.
int calendarDays(DateTime local, DateTime from) => DateTime.utc(
  local.year,
  local.month,
  local.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// When [at] is, in local time, from [now]: today or tomorrow at a time, or a date and time.
String whenText(DateTime at, DateTime now) {
  final local = at.toLocal();
  final days = calendarDays(local, now);
  final time = clockText(local);
  return switch (days) {
    0 => 'today $time',
    1 => 'tomorrow $time',
    -1 => 'yesterday $time',
    _ => '${_dateText(local)}, $time',
  };
}

/// The day [at] falls on, in local time, as [now] gives it: Today, Yesterday, or `Mon 6 Oct`.
String dayText(DateTime at, DateTime now) {
  final local = at.toLocal();
  final days = calendarDays(local, now);
  return switch (days) {
    0 => 'Today',
    -1 => 'Yesterday',
    _ => _dateText(local),
  };
}
