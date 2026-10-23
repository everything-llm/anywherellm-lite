import 'package:anywherellm/core/page_status.dart';
import 'package:anywherellm/core/skill_pages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PageStatus', () {
    test('reads the failed runs and the changed apps', () {
      final status = PageStatus.fromJson({
        'library': {
          'failed': ['2026-10-23T08:00:00.000Z', 'not a time', 3],
        },
        'apps': {
          'changed': ['2026-10-23T09:00:00Z'],
        },
      });
      expect(status.failed, [DateTime.utc(2026, 10, 23, 8)]);
      expect(status.changed, [DateTime.utc(2026, 10, 23, 9)]);
    });

    test(
      'a key absent or not a list is unknown, and an empty list is none',
      () {
        expect(PageStatus.fromJson(null).failed, isNull);
        expect(
          PageStatus.fromJson({
            'library': {'failed': 'x'},
          }).failed,
          isNull,
        );
        expect(
          PageStatus.fromJson({
            'apps': {'changed': []},
          }).changed,
          isEmpty,
        );
        expect(
          PageStatus.fromJson({
            'apps': {'changed': []},
          }).failed,
          isNull,
        );
      },
    );
  });

  group('the Apps line', () {
    final now = DateTime(2026, 10, 23, 15);

    test('counts the changes on the phone\'s own date', () {
      expect(
        appsChangedLine([
          DateTime(2026, 10, 23, 14).toUtc(),
          DateTime(2026, 10, 23, 0, 5).toUtc(),
          DateTime(2026, 10, 22, 23, 55).toUtc(),
        ], now),
        '2 changed today',
      );
    });

    test('is null with none today, and says more at the bridge\'s cap', () {
      expect(appsChangedLine([DateTime(2026, 10, 22, 9)], now), isNull);
      expect(
        appsChangedLine(
          List.filled(changedListed, DateTime(2026, 10, 23, 9)),
          now,
        ),
        '50+ changed today',
      );
    });
  });

  group('the Library line', () {
    final failed = [
      DateTime.utc(2026, 10, 23, 9),
      DateTime.utc(2026, 10, 23, 8),
    ];

    test('counts the runs that failed since the Library was seen', () {
      expect(
        libraryFailedLine(failed, DateTime.utc(2026, 10, 23, 8, 30)),
        '1 run failed',
      );
      expect(libraryFailedLine(failed, DateTime.utc(2026, 10, 23, 10)), isNull);
    });

    test('counts every one when it was never seen', () {
      expect(libraryFailedLine(failed, null), '2 runs failed');
      expect(
        libraryFailedLine(
          List.filled(failedListed, DateTime.utc(2026, 10, 23)),
          null,
        ),
        '20+ runs failed',
      );
    });
  });

  test('pageNews gives each row its own news, and none to the others', () {
    final status = PageStatus(
      failed: [DateTime.utc(2026, 10, 23, 9)],
      changed: [DateTime(2026, 10, 23, 9).toUtc()],
    );
    final now = DateTime(2026, 10, 23, 15);
    expect(pageNews(SkillPage.library, status, seen: null, now: now), (
      line: '1 run failed',
      failed: true,
    ));
    expect(pageNews(SkillPage.appsManager, status, seen: null, now: now), (
      line: '1 changed today',
      failed: false,
    ));
    expect(pageNews(SkillPage.vault, status, seen: null, now: now), (
      line: null,
      failed: false,
    ));
    expect(
      pageNews(SkillPage.library, const PageStatus(), seen: null, now: now),
      (line: null, failed: false),
    );
  });
}
