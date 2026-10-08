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
    expect(describeSchedule('0 7 * * *', now), 'Every day at ${local(7, 0)}');
  });

  test('a schedule it cannot say plainly shows as cron, in UTC', () {
    expect(describeSchedule('0 7 1 * *', now), '0 7 1 * * (UTC)');
    expect(describeSchedule('nonsense', now), 'nonsense (UTC)');
    expect(describeSchedule('', now), 'No schedule');
  });

  test('a job reads from the server\'s list, a workspace in any form', () {
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
          'workspace': {'name': 'Household', 'slug': 'household'},
        },
        {
          'name': 'Off one',
          'schedule': '0 9 * * 1',
          'enabled': false,
          'workspaceSlug': 'q3',
        },
        {'schedule': '* * * * *'},
      ],
    });
    expect(jobs.map((j) => j.name), ['Morning brief', 'Off one']);
    expect(jobs.first.workspace, 'Household');
    expect(jobs.first.lastStatus, 'completed');
    expect(jobs.first.nextRun, DateTime.utc(2026, 10, 9, 7));
    expect(jobs.last.workspace, 'q3');
    expect(jobs.last.enabled, isFalse);
  });

  test('a time reads as today, tomorrow or a date', () {
    final today = DateTime(2026, 10, 8, 18, 30);
    expect(whenText(today, now), 'today 18:30');
    expect(whenText(today.add(const Duration(days: 1)), now), 'tomorrow 18:30');
    expect(whenText(DateTime(2026, 10, 13, 7), now), 'Tue 13 Oct, 07:00');
  });
}
