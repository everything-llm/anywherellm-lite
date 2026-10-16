import 'copy.dart';
import 'schedule.dart';

/// How often a scheduled task runs, as the New task sheet offers it.
enum Repeat { daily, weekly, custom }

/// The least a cron may leave between runs, in minutes. The app refuses a faster one, since a job
/// spends the model's time with no one watching.
const minJobGap = 5;

/// What is wrong with the cron [text], in plain words, or null when it is a schedule the app
/// sends: five fields that do not fire more often than every [minJobGap] minutes, across the
/// turn of an hour too.
String? cronProblem(String text) {
  final parts = cronFields(text);
  if (parts.length != 5 || !parts.every(_field.hasMatch)) {
    return 'A schedule is five fields, such as 0 */6 * * *.';
  }
  final gap = _minuteGap(parts[0], parts[1]);
  if (gap != null && gap < minJobGap) {
    return 'That runs more often than every $minJobGap minutes. Leave more time between runs.';
  }
  return null;
}

final _item = RegExp(r'^(?:\*|(\d+)(?:-(\d+))?)(?:/(\d+))?$');

/// The values the cron [field] allows, from 0 to [last]: `*`, `*/N`, `A-B`, `A-B/N`, `A/N` and
/// numbers, joined by commas. Null for a field this does not read; empty for a step of 0.
Set<int>? _values(String field, int last) {
  final values = <int>{};
  for (final item in field.split(',')) {
    final match = _item.firstMatch(item);
    if (match == null) return null;
    final star = item.startsWith('*');
    final step = int.parse(match[3] ?? '1');
    final from = star ? 0 : int.parse(match[1]!);
    final to = star || (match[2] == null && match[3] != null)
        ? last
        : int.parse(match[2] ?? match[1]!);
    if (step < 1) return {};
    if (from > to || to > last) return null;
    for (var at = from; at <= to; at += step) {
      values.add(at);
    }
  }
  return values;
}

/// The least gap, in minutes, between two runs that the cron [minutes] and [hours] fields allow:
/// within an hour, and from an hour's last run to the next hour's first when [hours] holds two
/// hours in a row. Null for a field this does not read, or for one run an hour in hours that
/// never follow one another; 0 for a step of 0.
int? _minuteGap(String minutes, String hours) {
  final values = _values(minutes, 59);
  if (values == null) return null;
  if (values.isEmpty) return 0;
  final sorted = values.toList()..sort();
  final inHours = _values(hours, 23);
  // The next hour's first run, when the hours run on into it.
  if (inHours != null && inHours.any((h) => inHours.contains((h + 1) % 24))) {
    sorted.add(sorted.first + 60);
  }
  int? least;
  for (var i = 1; i < sorted.length; i++) {
    final gap = sorted[i] - sorted[i - 1];
    if (least == null || gap < least) least = gap;
  }
  return least;
}

final _field = RegExp(r'^[\d*/,\-]+$');

/// When a task runs, as a person writes it in the sheet: daily or weekly at a time of day in
/// their own time, or a cron of their own. [toCron] turns it into the UTC cron AnythingLLM stores
/// and [fromCron] reads one back for Edit.
class ScheduleSpec {
  const ScheduleSpec({
    this.repeat = Repeat.daily,
    this.hour = 7,
    this.minute = 0,
    this.days = const {},
    this.cron = '',
  });

  final Repeat repeat;

  /// The time of day in local time.
  final int hour;
  final int minute;

  /// The weekdays of a weekly task, `DateTime.monday` to `DateTime.sunday`.
  final Set<int> days;

  /// A custom task's cron, in UTC.
  final String cron;

  ScheduleSpec copyWith({
    Repeat? repeat,
    int? hour,
    int? minute,
    Set<int>? days,
    String? cron,
  }) => ScheduleSpec(
    repeat: repeat ?? this.repeat,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    days: days ?? this.days,
    cron: cron ?? this.cron,
  );

  /// Reads [cron], which runs in UTC, back as a spec in local time, as [now] gives it. A cron
  /// that is not a time of day or days of the week is a custom one.
  static ScheduleSpec fromCron(String cron, DateTime now) {
    final custom = ScheduleSpec(repeat: Repeat.custom, cron: cron.trim());
    final parts = cronFields(cron);
    if (parts.length != 5) return custom;
    final [minute, hour, day, month, weekday] = parts;
    final m = int.tryParse(minute);
    final h = int.tryParse(hour);
    if (m == null || h == null || m > 59 || h > 23) return custom;
    final at = DateTime.utc(now.year, now.month, now.day, h, m).toLocal();
    final shift = calendarDays(at, now);
    if (day == '*' && month == '*' && weekday == '*') {
      return ScheduleSpec(hour: at.hour, minute: at.minute);
    }
    if (day == '*' && month == '*') {
      final listed = [for (final d in weekday.split(',')) int.tryParse(d)];
      if (listed.any((d) => d == null || d > 7)) return custom;
      return ScheduleSpec(
        repeat: Repeat.weekly,
        hour: at.hour,
        minute: at.minute,
        days: {
          for (final d in listed) ((((d! == 0 ? 7 : d) + shift - 1) % 7) + 1),
        },
      );
    }
    return custom;
  }

  /// What is wrong with the spec, in plain words, or null when [toCron] has a cron for it.
  String? problem() {
    switch (repeat) {
      case Repeat.daily:
        return null;
      case Repeat.weekly:
        return days.isEmpty ? 'Pick at least one day.' : null;
      case Repeat.custom:
        return cronProblem(cron);
    }
  }

  /// The UTC cron AnythingLLM stores for the spec, as [now]'s clock offset gives it, or null
  /// while [problem] says something is wrong.
  String? toCron(DateTime now) {
    if (problem() != null) return null;
    if (repeat == Repeat.custom) return cron.trim();
    // The time of day in UTC as today's offset gives it, and how many days that moves the day.
    final utc = DateTime(now.year, now.month, now.day, hour, minute).toUtc();
    final at = '${utc.minute} ${utc.hour}';
    if (repeat == Repeat.daily) return '$at * * *';
    final shift = calendarDays(
      DateTime(now.year, now.month, now.day, hour, minute),
      DateTime.utc(utc.year, utc.month, utc.day),
    );
    // Cron counts Sunday as 0; a day's weekday moves by the shift from local to UTC.
    final cronDays = {
      for (final d in days) ((((d - 1) - shift) % 7 + 7) % 7 + 1) % 7,
    }.toList()..sort();
    return '$at * * ${cronDays.join(',')}';
  }

  /// A line under the sheet's schedule: when the task runs in the person's own time, and that a
  /// custom cron runs in UTC. Where the clocks change, a time of day moves an hour with them.
  String caption(DateTime now) {
    final problem = this.problem();
    if (problem != null) return problem;
    final time = clockText(DateTime(0, 1, 1, hour, minute));
    final base = switch (repeat) {
      Repeat.daily => 'Runs every day at $time your time.',
      Repeat.weekly =>
        'Runs on ${_andList([for (final d in (days.toList()..sort())) '${weekdayNames[d - 1]}s'])} at $time your time.',
      Repeat.custom =>
        '${describeSchedule(cron.trim(), now)}. Custom schedules run in UTC.',
    };
    final moves =
        (repeat == Repeat.daily || repeat == Repeat.weekly) &&
        _observesDst(now);
    return moves ? '$base It moves an hour when the clocks change.' : base;
  }

  /// Whether the clocks change in [now]'s time zone within the year.
  static bool _observesDst(DateTime now) => [
    for (var months = 1; months <= 11; months++)
      DateTime(now.year, now.month + months, 1).timeZoneOffset,
  ].any((offset) => offset != now.timeZoneOffset);
}

String _andList(List<String> items) => items.length < 2
    ? items.join()
    : '${items.take(items.length - 1).join(', ')} and ${items.last}';
