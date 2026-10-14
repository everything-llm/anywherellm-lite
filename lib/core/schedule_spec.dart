import 'copy.dart';
import 'schedule.dart';

/// How often a scheduled task runs, as the New task sheet offers it.
enum Repeat { once, daily, weekly, custom }

/// The least a cron may leave between runs, in minutes. The toolkit refuses a faster one, since a
/// job spends the model's time with no one watching.
const minJobGap = 5;

/// What is wrong with the cron [text], in plain words, or null when it is a schedule the toolkit
/// takes: five fields, and a minute field that does not fire more often than every
/// [minJobGap] minutes.
String? cronProblem(String text) {
  final parts = text.trim().split(RegExp(r'\s+'));
  if (parts.length != 5 || !parts.every(_field.hasMatch)) {
    return 'A schedule is five fields, such as 0 */6 * * *.';
  }
  final minute = parts.first;
  if (minute == '*' || (cronStep(minute) ?? minJobGap) < minJobGap) {
    return 'That runs more often than every $minJobGap minutes. The toolkit does not allow it.';
  }
  return null;
}

final _field = RegExp(r'^[\d*/,\-]+$');

/// When a task runs, as a person writes it in the sheet: daily or weekly at a time of day in
/// their own time, once on a date, or a cron of their own. [toCron] turns it into the UTC cron
/// the toolkit stores and [fromCron] reads one back for Edit.
class ScheduleSpec {
  const ScheduleSpec({
    this.repeat = Repeat.daily,
    this.hour = 7,
    this.minute = 0,
    this.days = const {},
    this.date,
    this.cron = '',
  });

  final Repeat repeat;

  /// The time of day in local time.
  final int hour;
  final int minute;

  /// The weekdays of a weekly task, `DateTime.monday` to `DateTime.sunday`.
  final Set<int> days;

  /// The local date of a task that runs once.
  final DateTime? date;

  /// A custom task's cron, in UTC.
  final String cron;

  ScheduleSpec copyWith({
    Repeat? repeat,
    int? hour,
    int? minute,
    Set<int>? days,
    DateTime? date,
    String? cron,
  }) => ScheduleSpec(
    repeat: repeat ?? this.repeat,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    days: days ?? this.days,
    date: date ?? this.date,
    cron: cron ?? this.cron,
  );

  /// Reads [cron], which runs in UTC, back as a spec in local time, as [now] gives it. A cron
  /// that is not a time of day, one day a week or one date is a custom one.
  static ScheduleSpec fromCron(String cron, DateTime now) {
    final custom = ScheduleSpec(repeat: Repeat.custom, cron: cron.trim());
    final parts = cron.trim().split(RegExp(r'\s+'));
    if (parts.length != 5) return custom;
    final [minute, hour, day, month, weekday] = parts;
    final m = int.tryParse(minute);
    final h = int.tryParse(hour);
    if (m == null || h == null || m > 59 || h > 23) return custom;
    final at = DateTime.utc(now.year, now.month, now.day, h, m).toLocal();
    final shift = _dayShift(at, DateTime.utc(now.year, now.month, now.day));
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
    final dom = int.tryParse(day);
    final mon = int.tryParse(month);
    if (dom != null && mon != null && weekday == '*') {
      final local = DateTime.utc(now.year, mon, dom, h, m).toLocal();
      return ScheduleSpec(
        repeat: Repeat.once,
        hour: local.hour,
        minute: local.minute,
        date: DateTime(local.year, local.month, local.day),
      );
    }
    return custom;
  }

  /// The days between [local]'s date and [from]'s, as UTC dates, so a clock change between the
  /// two cannot make a day 23 hours.
  static int _dayShift(DateTime local, DateTime from) => DateTime.utc(
    local.year,
    local.month,
    local.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  /// What is wrong with the spec, in plain words, or null when [toCron] has a cron for it.
  String? problem(DateTime now) {
    switch (repeat) {
      case Repeat.daily:
        return null;
      case Repeat.weekly:
        return days.isEmpty ? 'Pick at least one day.' : null;
      case Repeat.once:
        final at = _once();
        if (at == null) return 'Pick a date.';
        return at.isAfter(now) ? null : 'That time has passed.';
      case Repeat.custom:
        return cronProblem(cron);
    }
  }

  DateTime? _once() => date == null
      ? null
      : DateTime(date!.year, date!.month, date!.day, hour, minute);

  /// The UTC cron the toolkit stores for the spec, as [now]'s clock offset gives it, or null
  /// while [problem] says something is wrong.
  String? toCron(DateTime now) {
    if (problem(now) != null) return null;
    if (repeat == Repeat.custom) return cron.trim();
    if (repeat == Repeat.once) {
      final utc = _once()!.toUtc();
      return '${utc.minute} ${utc.hour} ${utc.day} ${utc.month} *';
    }
    // The time of day in UTC as today's offset gives it, and how many days that moves the day.
    final utc = DateTime(now.year, now.month, now.day, hour, minute).toUtc();
    final at = '${utc.minute} ${utc.hour}';
    if (repeat == Repeat.daily) return '$at * * *';
    final shift = _dayShift(
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
    final problem = this.problem(now);
    if (problem != null) return problem;
    final time = clockText(DateTime(0, 1, 1, hour, minute));
    final base = switch (repeat) {
      Repeat.daily => 'Runs every day at $time your time.',
      Repeat.weekly =>
        'Runs on ${_andList([for (final d in (days.toList()..sort())) '${weekdayNames[d - 1]}s'])} at $time your time.',
      Repeat.once => 'Runs once, ${dateText(date!)} at $time your time.',
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
