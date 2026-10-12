import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/ui/upcoming.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('the phone\'s drawer counts the jobs and opens Upcoming', (
    tester,
  ) async {
    final llm = planningServer()
      ..jobs = [
        ScheduledJob(
          name: 'Morning brief',
          cron: '*/30 * * * *',
          workspace: 'Household',
          nextRun: DateTime.now().toUtc().add(const Duration(hours: 1)),
          lastStatus: 'completed',
        ),
        const ScheduledJob(
          name: 'Weekly report',
          cron: '0 9 * * 1',
          enabled: false,
        ),
      ];
    final h = await pumpApp(tester, llm: llm, onChat: false);
    expect(find.textContaining('2 jobs · next today'), findsOneWidget);
    await tester.tap(find.text('Upcoming'));
    await tester.pumpAndSettle();
    final page = find.byType(UpcomingPage);
    expect(page, findsOneWidget);
    expect(find.text('Morning brief'), findsOneWidget);
    expect(
      find.textContaining('Household · Every 30 minutes · Next: '),
      findsOneWidget,
    );
    expect(find.textContaining(' · Off'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.shell.upcomingOpen, isFalse);
  });

  testWidgets('without the password Upcoming says why and offers Connection', (
    tester,
  ) async {
    final llm = planningServer()
      ..errors['scheduledJobs'] = const ApiException(
        'This needs the server password. Add it in Settings.',
        status: 401,
      );
    final h = await pumpApp(tester, llm: llm);
    h.shell.openUpcoming();
    await tester.pumpAndSettle();
    expect(find.textContaining('server password'), findsOneWidget);
    await tester.tap(control('Open Connection'));
    await tester.pumpAndSettle();
    expect(h.shell.upcomingOpen, isFalse);
    expect(h.shell.settingsOpen, isTrue);
  });
}
