import 'package:anywherellm/core/activity.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a span reads in its shortest whole unit', () {
    expect(elapsedText(const Duration(seconds: 40)), '40 s');
    expect(elapsedText(const Duration(minutes: 3, seconds: 20)), '3 min');
    expect(elapsedText(const Duration(hours: 5, minutes: 59)), '5 h');
    expect(elapsedText(const Duration(days: 1, hours: 2)), '1 day');
    expect(elapsedText(const Duration(days: 4)), '4 days');
    expect(elapsedText(const Duration(seconds: -3)), '0 s');
  });

  test('how long ago names yesterday and says just now for a moment', () {
    final now = DateTime.utc(2026, 10, 8, 12);
    String ago(Duration d) => agoText(now.subtract(d), now);
    expect(ago(const Duration(seconds: 20)), 'just now');
    expect(ago(const Duration(minutes: 12)), '12 min ago');
    expect(ago(const Duration(hours: 1, minutes: 5)), '1 h ago');
    expect(ago(const Duration(hours: 30)), 'yesterday');
    expect(ago(const Duration(days: 2, hours: 3)), '2 days ago');
  });

  test('runs split into those running and those ended, each newest first', () {
    RelayRun run(String id, String status, int minutes, {int? ended}) =>
        RelayRun(
          id: id,
          workspace: 'w',
          thread: 't',
          status: status,
          started: DateTime.utc(2026, 10, 8, 12, minutes),
          finished: ended == null ? null : DateTime.utc(2026, 10, 8, 13, ended),
        );
    final groups = activityGroups([
      run('old', 'running', 1),
      run('done-early', 'done', 5, ended: 2),
      run('new', 'running', 9),
      run('done-late', 'failed', 3, ended: 8),
      const RelayRun(workspace: 'w', thread: 't', status: 'done', id: 'bare'),
    ]);
    expect([for (final r in groups.running) r.id], ['new', 'old']);
    expect(
      [for (final r in groups.ended) r.id],
      ['done-late', 'done-early', 'bare'],
    );
  });
}
