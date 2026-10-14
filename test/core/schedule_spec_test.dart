import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/core/schedule_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A Thursday.
  final now = DateTime(2026, 10, 8, 10);

  group('a time of day in local time and the UTC cron the toolkit stores', () {
    test('a daily task is the local time turned into UTC', () {
      final spec = ScheduleSpec(hour: 7, minute: 30);
      final utc = DateTime(2026, 10, 8, 7, 30).toUtc();
      expect(spec.toCron(now), '${utc.minute} ${utc.hour} * * *');
      final back = ScheduleSpec.fromCron(spec.toCron(now)!, now);
      expect(back.repeat, Repeat.daily);
      expect((back.hour, back.minute), (7, 30));
    });

    test('a weekly task keeps its weekdays across a day boundary', () {
      // Just after midnight, where a zone east or west of UTC moves the day.
      for (final (hour, minute) in [(0, 20), (12, 0), (23, 40)]) {
        final spec = ScheduleSpec(
          repeat: Repeat.weekly,
          hour: hour,
          minute: minute,
          days: {DateTime.monday, DateTime.thursday, DateTime.sunday},
        );
        final cron = spec.toCron(now)!;
        final back = ScheduleSpec.fromCron(cron, now);
        expect(back.repeat, Repeat.weekly, reason: cron);
        expect(back.days, spec.days, reason: cron);
        expect((back.hour, back.minute), (hour, minute), reason: cron);
      }
    });

    test('a task that runs once is a cron with its date', () {
      final spec = ScheduleSpec(
        repeat: Repeat.once,
        hour: 9,
        minute: 0,
        date: DateTime(2026, 10, 17),
      );
      final cron = spec.toCron(now)!;
      final utc = DateTime(2026, 10, 17, 9).toUtc();
      expect(cron, '${utc.minute} ${utc.hour} ${utc.day} ${utc.month} *');
      final back = ScheduleSpec.fromCron(cron, now);
      expect(back.repeat, Repeat.once);
      expect(back.date, DateTime(2026, 10, 17));
      expect((back.hour, back.minute), (9, 0));
    });
  });

  group('what is wrong with a schedule', () {
    test('a weekly task needs a day, a one-off a date still to come', () {
      expect(
        const ScheduleSpec(repeat: Repeat.weekly).problem(now),
        'Pick at least one day.',
      );
      expect(
        const ScheduleSpec(repeat: Repeat.once).problem(now),
        'Pick a date.',
      );
      expect(
        ScheduleSpec(
          repeat: Repeat.once,
          hour: 9,
          date: DateTime(2026, 10, 8),
        ).problem(now),
        'That time has passed.',
      );
      expect(const ScheduleSpec().problem(now), isNull);
    });

    test('a cron is five fields and not more often than every 5 minutes', () {
      expect(cronProblem('0 */6 * * *'), isNull);
      expect(cronProblem('*/5 * * * *'), isNull);
      expect(cronProblem('30 17 * * 5'), isNull);
      expect(cronProblem('* * * * *'), contains('more often than every 5'));
      expect(cronProblem('*/4 * * * *'), contains('more often than every 5'));
      expect(cronProblem('nonsense'), contains('five fields'));
      expect(cronProblem('0 6 * * mon'), contains('five fields'));
      expect(
        const ScheduleSpec(
          repeat: Repeat.custom,
          cron: '* * * * *',
        ).toCron(now),
        isNull,
      );
    });

    test('a custom cron reads back as custom, and says it runs in UTC', () {
      final spec = ScheduleSpec.fromCron('0 7 1 * *', now);
      expect(spec.repeat, Repeat.custom);
      expect(spec.cron, '0 7 1 * *');
      expect(spec.caption(now), contains('Custom schedules run in UTC.'));
    });
  });

  test('the caption says when the task runs, in the person\'s time', () {
    expect(
      const ScheduleSpec(hour: 6, minute: 30).caption(now),
      startsWith('Runs every day at 06:30 your time.'),
    );
    expect(
      const ScheduleSpec(
        repeat: Repeat.weekly,
        hour: 8,
        days: {DateTime.monday, DateTime.thursday},
      ).caption(now),
      startsWith('Runs on Mondays and Thursdays at 08:00 your time.'),
    );
    expect(
      ScheduleSpec(
        repeat: Repeat.once,
        hour: 9,
        date: DateTime(2026, 10, 17),
      ).caption(now),
      'Runs once, Sat 17 Oct at 09:00 your time.',
    );
    expect(
      const ScheduleSpec(repeat: Repeat.weekly).caption(now),
      'Pick at least one day.',
    );
  });

  group('a job and its runs as the toolkit lists them', () {
    test('a job carries its id, prompt, action and workspace slug', () {
      final job = ScheduledJob.fromJson({
        'id': 7,
        'name': 'Price watch',
        'schedule': '0 */6 * * *',
        'prompt': '',
        'runAction': 'Check the boiler service price',
        'workspace': {'name': 'Household', 'slug': 'household'},
      })!;
      expect(job.id, '7');
      expect(job.action, 'Check the boiler service price');
      expect(job.workspace, 'Household');
      expect(job.workspaceSlug, 'household');
      final plain = ScheduledJob.fromJson({
        'id': 'abc',
        'name': 'Brief',
        'schedule': '0 7 * * *',
        'prompt': 'Summarise today.',
        'workspaceSlug': 'home',
      })!;
      expect(plain.id, 'abc');
      expect(plain.prompt, 'Summarise today.');
      expect(plain.action, isNull);
      expect(plain.workspaceSlug, 'home');
      expect(
        ScheduledJob.fromJson({'name': 'Old', 'schedule': ''})!.id,
        isNull,
      );
    });

    test('runs read newest first, with how each ended', () {
      final runs = jobRunsOf({
        'runs': [
          {'status': 'running', 'startedAt': '2026-10-08T07:00:00Z'},
          {'status': 'failed', 'result': 'The site answered 503'},
          {'status': 'completed', 'result': 'Done.'},
          'nonsense',
        ],
      });
      expect(runs, hasLength(3));
      expect(runs[0].running, isTrue);
      expect(runs[0].wentWell, isNull);
      expect(runs[1].wentWell, isFalse);
      expect(runs[1].result, 'The site answered 503');
      expect(runs[2].wentWell, isTrue);
    });

    test('a draft is what the toolkit takes', () {
      expect(
        const JobDraft(
          name: 'Brief',
          prompt: 'Summarise today.',
          workspaceSlug: 'home',
          cron: '0 7 * * *',
          once: true,
        ).toJson(),
        {
          'name': 'Brief',
          'prompt': 'Summarise today.',
          'workspace': 'home',
          'schedule': '0 7 * * *',
          'once': true,
          'enabled': true,
        },
      );
    });
  });
}
