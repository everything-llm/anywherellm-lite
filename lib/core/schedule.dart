import 'copy.dart';
import 'server_models.dart' show jsonObjects;

/// A job AnythingLLM runs on a schedule: its [name], the [workspace] it runs in when the server
/// says, its [cron] schedule in UTC, whether it is [enabled], when it runs next and last, and
/// how its latest run went.
class ScheduledJob {
  const ScheduledJob({
    required this.name,
    required this.cron,
    this.workspace,
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
    return ScheduledJob(
      name: name,
      cron: json['schedule'] is String ? json['schedule'] as String : '',
      workspace: switch (json['workspace']) {
        {'name': final String name} => name,
        final String slug => slug,
        _ =>
          json['workspaceSlug'] is String
              ? json['workspaceSlug'] as String
              : null,
      },
      enabled: json['enabled'] != false,
      nextRun: _time(json['nextRunAt']),
      lastRun:
          _time(json['lastRunAt']) ??
          (latest is Map ? _time(latest['startedAt']) : null),
      lastStatus: latest is Map && latest['status'] is String
          ? latest['status'] as String
          : null,
    );
  }

  final String name;
  final String? workspace;
  final String cron;
  final bool enabled;
  final DateTime? nextRun;
  final DateTime? lastRun;

  /// How the latest run ended, in the server's word, such as `completed` or `failed`.
  final String? lastStatus;
}

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

/// The jobs in a `/api/scheduled-jobs` answer: a list, or an object with them under `jobs`.
List<ScheduledJob> scheduledJobsOf(Object? json) => [
  for (final job in jsonObjects(json is Map ? json['jobs'] : json))
    ?ScheduledJob.fromJson(job),
];

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// [cron], which runs in UTC, in plain words in local time, as [now] gives it: every few
/// minutes, every hour, every day, every weekday or one day a week. Any other schedule is the
/// cron itself, marked UTC.
String describeSchedule(String cron, DateTime now) {
  final parts = cron.trim().split(RegExp(r'\s+'));
  if (parts.length != 5) return cron.isEmpty ? 'No schedule' : '$cron (UTC)';
  final [minute, hour, day, month, weekday] = parts;
  if (day != '*' || month != '*') return '$cron (UTC)';
  if (RegExp(r'^\*/(\d+)$').firstMatch(minute) case final every?
      when hour == '*' && weekday == '*') {
    final n = int.parse(every.group(1)!);
    return n == 1 ? 'Every minute' : 'Every ${plural(n, 'minute', 'minutes')}';
  }
  final m = int.tryParse(minute);
  if (m == null || m > 59) return '$cron (UTC)';
  if (hour == '*' && weekday == '*') {
    return 'Every hour at :${m.toString().padLeft(2, '0')}';
  }
  final h = int.tryParse(hour);
  if (h == null || h > 23) return '$cron (UTC)';
  final utcNow = now.toUtc();
  // The time in local time, and how many days that moves the day.
  final at = DateTime.utc(utcNow.year, utcNow.month, utcNow.day, h, m);
  final local = at.toLocal();
  final shift = DateTime(
    local.year,
    local.month,
    local.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
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
  return 'Every ${_days[(monday0 + shift) % 7]} at $time';
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
    _ =>
      '${_days[local.weekday - 1]} ${local.day} ${monthNames[local.month - 1]}, '
          '$time',
  };
}
