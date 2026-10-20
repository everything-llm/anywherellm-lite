import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/core/schedule_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A Thursday.
  final now = DateTime(2026, 10, 8, 10);

  group('a time of day in local time and the UTC cron AnythingLLM stores', () {
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
  });

  group('what is wrong with a schedule', () {
    test('a weekly task needs a day', () {
      expect(
        const ScheduleSpec(repeat: Repeat.weekly).problem(),
        'Pick at least one day.',
      );
      expect(const ScheduleSpec().problem(), isNull);
    });

    test('a cron is five fields and not more often than every 5 minutes', () {
      expect(cronProblem('0 */6 * * *'), isNull);
      expect(cronProblem('*/5 * * * *'), isNull);
      expect(cronProblem('30 17 * * 5'), isNull);
      expect(cronProblem('* * * * *'), contains('more often than every 5'));
      expect(cronProblem('*/4 * * * *'), contains('more often than every 5'));
      expect(cronProblem('0,1,2 * * * *'), contains('more often than every 5'));
      expect(cronProblem('0-30 * * * *'), contains('more often than every 5'));
      expect(cronProblem('0,15,30,45 * * * *'), isNull);
      expect(cronProblem('0,59 * * * *'), contains('more often than every 5'));
      expect(cronProblem('58,2 * * * *'), contains('more often than every 5'));
      expect(
        cronProblem('0,59 5-6 * * *'),
        contains('more often than every 5'),
      );
      expect(
        cronProblem('0,59 23,0 * * *'),
        contains('more often than every 5'),
      );
      expect(cronProblem('0,59 5 * * *'), isNull);
      expect(cronProblem('0,59 5,7 * * *'), isNull);
      expect(cronProblem('nonsense'), contains('five fields'));
      expect(cronProblem('0 6 * * mon'), contains('five fields'));
      expect(cronProblem('0 99999999999999999999 * * *'), contains('range'));
      expect(cronProblem('*/99999999999999999999 * * * *'), contains('range'));
      expect(cronProblem('0 25 * * *'), contains('range'));
      expect(cronProblem('0 6 * * 99999999999999999999'), isNull);
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
      // A date, which a task that ran once used to be, is custom too.
      expect(ScheduleSpec.fromCron('0 9 17 10 *', now).repeat, Repeat.custom);
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
      const ScheduleSpec(repeat: Repeat.weekly).caption(now),
      'Pick at least one day.',
    );
  });

  group('a job and its runs as AnythingLLM lists them', () {
    test('a job carries its id, prompt and how many tools it may use', () {
      final job = ScheduledJob.fromJson({
        'id': 7,
        'name': 'Price watch',
        'schedule': '0 */6 * * *',
        'prompt': 'Check the boiler service price.',
        'tools': '["web-scraping","web-browsing"]',
        'enabled': false,
        'latestRun': {'status': 'timed_out'},
      })!;
      expect(job.id, '7');
      expect(job.prompt, 'Check the boiler service price.');
      expect(job.tools, 2);
      expect(job.enabled, isFalse);
      expect(job.lastWentWell, isFalse);
      final plain = ScheduledJob.fromJson({
        'id': 'abc',
        'name': 'Brief',
        'schedule': '0 7 * * *',
        'prompt': 'Summarise today.',
        'tools': null,
      })!;
      expect(plain.id, 'abc');
      expect(plain.tools, 0);
      expect(
        ScheduledJob.fromJson({'name': 'Old', 'schedule': ''})!.id,
        isNull,
      );
    });

    test('runs read newest first, with how each ended and what it said', () {
      final runs = jobRunsOf({
        'runs': [
          {'status': 'queued', 'startedAt': '2026-10-08T07:00:00Z'},
          {
            'status': 'failed',
            'result': null,
            'error': 'The site answered 503',
          },
          {
            'status': 'completed',
            'result': '{"text":"Done. ","sources":[],"outputs":[]}',
          },
          {'status': 'timed_out', 'result': null, 'error': null},
          'nonsense',
        ],
      });
      expect(runs, hasLength(4));
      expect(runs[0].running, isTrue);
      expect(runs[0].wentWell, isNull);
      expect(runs[1].wentWell, isFalse);
      expect(runs[1].result, 'The site answered 503');
      expect(runs[2].wentWell, isTrue);
      expect(runs[2].result, 'Done.');
      expect(runs[3].wentWell, isFalse);
      expect(runs[3].result, isNull);
    });

    test('a draft is what AnythingLLM takes, without tools or a switch', () {
      expect(
        const JobDraft(
          name: 'Brief',
          prompt: 'Summarise today.',
          cron: '0 7 * * *',
        ).toJson(),
        {
          'name': 'Brief',
          'prompt': 'Summarise today.',
          'schedule': '0 7 * * *',
        },
      );
    });
  });
}
