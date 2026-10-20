import 'package:anywherellm/core/schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 8, 10);
  String local(int h, int m) {
    final at = DateTime.utc(2026, 10, 8, h, m).toLocal();
    return '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
  }

  test('a schedule reads in plain words, in local time', () {
    expect(describeSchedule('*/15 * * * *', now), 'Every 15 minutes');
    expect(describeSchedule('5 * * * *', now), 'Every hour at :05');
    expect(describeSchedule('0 */6 * * *', now), 'Every 6 hours');
    expect(describeSchedule('0 */1 * * *', now), 'Every hour');
    expect(describeSchedule('0 7 * * *', now), 'Every day at ${local(7, 0)}');
  });

  test('a schedule it cannot say plainly shows as cron, in UTC', () {
    expect(describeSchedule('0 7 1 * *', now), '0 7 1 * * (UTC)');
    expect(describeSchedule('nonsense', now), 'nonsense (UTC)');
    expect(describeSchedule('', now), 'No schedule');
  });

  test('a weekly schedule names its days, moved by the time zone', () {
    // The weekdays of 14:00 UTC on `now`'s date, as local time moves them.
    String days(String cron) => describeSchedule(cron, now);
    final at = DateTime.utc(2026, 10, 8, 14).toLocal();
    final shift = at.day - 8;
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    String named(List<int> monday1) {
      final picked = {for (final d in monday1) (d - 1 + shift) % 7}.toList()
        ..sort();
      final shown = [for (final i in picked) names[i]];
      return shown.length < 2
          ? shown.join()
          : '${shown.take(shown.length - 1).join(', ')} and ${shown.last}';
    }

    final time = local(14, 0);
    expect(days('0 14 * * 1'), 'Every ${named([1])} at $time');
    expect(days('0 14 * * 0'), 'Every ${named([7])} at $time');
    expect(days('0 14 * * 7'), 'Every ${named([7])} at $time');
    expect(days('0 14 * * 1,3,5'), 'Every ${named([1, 3, 5])} at $time');
    expect(
      days('0 14 * * 1-5'),
      shift == 0
          ? 'Weekdays at $time'
          : 'Every ${named([1, 2, 3, 4, 5])} at $time',
    );
    expect(days('0 14 * * 1,x'), '0 14 * * 1,x (UTC)');
    expect(days('0 14 * * 1,9'), '0 14 * * 1,9 (UTC)');
  });

  test('a number too large for a cron field is not read', () {
    expect(
      describeSchedule('0 99999999999999999999 * * *', now),
      '0 99999999999999999999 * * * (UTC)',
    );
    expect(
      describeSchedule('*/99999999999999999999 * * * *', now),
      '*/99999999999999999999 * * * * (UTC)',
    );
  });

  test('a job reads from the server\'s list', () {
    final jobs = scheduledJobsOf({
      'jobs': [
        {
          'name': 'Morning brief',
          'schedule': '0 7 * * *',
          'nextRunAt': '2026-10-09T07:00:00Z',
          'lastRunAt': '2026-10-08T07:00:00Z',
          'enabled': true,
          'latestRun': {
            'status': 'completed',
            'startedAt': '2026-10-08T07:00:00Z',
          },
        },
        {'name': 'Off one', 'schedule': '0 9 * * 1', 'enabled': false},
        {'schedule': '* * * * *'},
      ],
    });
    expect(jobs.map((j) => j.name), ['Morning brief', 'Off one']);
    expect(jobs.first.lastStatus, 'completed');
    expect(jobs.first.nextRun, DateTime.utc(2026, 10, 9, 7));
    expect(jobs.last.enabled, isFalse);
  });

  test('a time reads as today, tomorrow or a date', () {
    final today = DateTime(2026, 10, 8, 18, 30);
    expect(whenText(today, now), 'today 18:30');
    expect(whenText(today.add(const Duration(days: 1)), now), 'tomorrow 18:30');
    expect(whenText(DateTime(2026, 10, 13, 7), now), 'Tue 13 Oct, 07:00');
  });

  test('the last run went well, badly or neither', () {
    ScheduledJob ran(String? status) =>
        ScheduledJob(name: 'Job', cron: '* * * * *', lastStatus: status);
    expect(ran('completed').lastWentWell, isTrue);
    expect(ran('failed').lastWentWell, isFalse);
    expect(ran('running').lastWentWell, isNull);
    expect(ran(null).lastWentWell, isNull);
  });
}
