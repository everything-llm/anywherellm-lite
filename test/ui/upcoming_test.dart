import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/upcoming.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_toolkit.dart';
import '../support/pump.dart';

void main() {
  testWidgets('the phone\'s drawer counts the jobs and opens Upcoming', (
    tester,
  ) async {
    final toolkit = FakeToolkit()
      ..jobs = [
        ScheduledJob(
          name: 'Morning brief',
          cron: '*/30 * * * *',
          nextRun: DateTime.now().toUtc().add(const Duration(hours: 1)),
          lastStatus: 'completed',
        ),
        const ScheduledJob(
          name: 'Weekly report',
          cron: '0 9 * * 1',
          enabled: false,
        ),
      ];
    final h = await pumpApp(
      tester,
      llm: planningServer(),
      toolkitServer: toolkit,
      shelf: true,
    );
    expect(find.textContaining('2 jobs · next today'), findsOneWidget);
    await tester.tap(find.text('Upcoming'));
    await tester.pumpAndSettle();
    final page = find.byType(UpcomingPage);
    expect(page, findsOneWidget);
    expect(find.text('Morning brief'), findsOneWidget);
    expect(find.textContaining('Every 30 minutes\nNext: '), findsOneWidget);
    expect(find.textContaining('\nOff'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.shell.toolkitPage, isNull);
  });

  testWidgets('a read the toolkit refuses says why and offers Connection', (
    tester,
  ) async {
    final toolkit = FakeToolkit()
      ..errors['scheduledJobs'] = const ApiException(
        'The toolkit did not accept the key.',
        status: 401,
      );
    final h = await pumpApp(tester, toolkitServer: toolkit);
    h.shell.openToolkitPage(ToolkitPage.upcoming);
    await tester.pumpAndSettle();
    expect(find.textContaining('did not accept the key'), findsOneWidget);
    await tester.tap(control('Open Connection'));
    await tester.pumpAndSettle();
    expect(h.shell.toolkitPage, isNull);
    expect(h.shell.settingsOpen, isTrue);
  });

  testWidgets('without the toolkit there is no Upcoming, and no Memory', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      toolkitServer: FakeToolkit(present: false),
      shelf: true,
    );
    expect(find.text('Upcoming'), findsNothing);
    h.shell.openSettings();
    await tester.pumpAndSettle();
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Memory'), findsNothing);
    await h.toolkitServer.features();
    expect(h.toolkitServer.calls, isNot(contains('scheduledJobs')));
  });

  testWidgets('an address a pairing code said for the toolkit asks it there', (
    tester,
  ) async {
    final toolkit = FakeToolkit(present: false);
    final h = await pumpApp(tester, toolkitServer: toolkit, shelf: true);
    expect(h.toolkit.available, isFalse);
    toolkit.present = true;
    await h.settings.pair(
      Pairing(sampleConnection, {
        toolkitCompanion.service: Uri.parse('https://toolkit.example.com'),
      }),
    );
    await tester.pumpAndSettle();
    expect(h.toolkit.available, isTrue);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
