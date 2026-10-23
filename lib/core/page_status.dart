import 'json.dart';
import 'schedule.dart';
import 'skill_pages.dart';

/// What the bridge's `GET /pages` says under `status` about the suite's pages: the end times of
/// the Library's failed runs, newest first ([failed]), and each app's last change, newest first
/// ([changed]); each null when it does not say. It holds times only, never text.
class PageStatus {
  const PageStatus({this.failed, this.changed});

  final List<DateTime>? failed;
  final List<DateTime>? changed;

  /// What [status] says, each list read from `library.failed` and `apps.changed`.
  static PageStatus fromJson(Object? status) => PageStatus(
    failed: _times(switch (status) {
      {'library': {'failed': final failed}} => failed,
      _ => null,
    }),
    changed: _times(switch (status) {
      {'apps': {'changed': final changed}} => changed,
      _ => null,
    }),
  );

  /// The ISO-8601 times in [list], or null when it is not a list. A time that does not parse
  /// is left out.
  static List<DateTime>? _times(Object? list) =>
      list is! List ? null : [for (final item in list) ?timeOrNull(item)];
}

/// The most failed runs the bridge lists.
const failedListed = 20;

/// The most app changes the bridge lists.
const changedListed = 50;

/// [count] in words, with a `+` when it is all of a list the bridge cut at [most].
String _counted(int count, int listed, int most) =>
    count == listed && listed >= most ? '$count+' : '$count';

/// The Apps row's line: how many apps of [changed] changed on [now]'s local date, as
/// `3 changed today`; null when none did.
String? appsChangedLine(List<DateTime> changed, DateTime now) {
  final count = changed
      .where((at) => calendarDays(at.toLocal(), now.toLocal()) == 0)
      .length;
  if (count == 0) return null;
  return '${_counted(count, changed.length, changedListed)} changed today';
}

/// The Library row's line: how many runs of [failed] failed after [seen], the newest failure
/// listed when the person last opened the Library from the app (null: never), as
/// `1 run failed`; null when none did.
String? libraryFailedLine(List<DateTime> failed, DateTime? seen) {
  final count = seen == null
      ? failed.length
      : failed.where((at) => at.isAfter(seen)).length;
  if (count == 0) return null;
  final runs = count == 1 ? 'run' : 'runs';
  return '${_counted(count, failed.length, failedListed)} $runs failed';
}

/// What [status] says is new on [page]'s row at [now], with the Library last [seen] as
/// [libraryFailedLine] takes it: the line, null when there is no news, and whether it says
/// something failed.
({String? line, bool failed}) pageNews(
  SkillPage page,
  PageStatus status, {
  required DateTime? seen,
  required DateTime now,
}) => switch ((page, status)) {
  (SkillPage.library, PageStatus(:final failed?)) => (
    line: libraryFailedLine(failed, seen),
    failed: true,
  ),
  (SkillPage.appsManager, PageStatus(:final changed?)) => (
    line: appsChangedLine(changed, now),
    failed: false,
  ),
  _ => (line: null, failed: false),
};
