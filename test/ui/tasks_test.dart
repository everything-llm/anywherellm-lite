import 'dart:async';

import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/task_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_toolkit.dart';
import '../support/pump.dart';

/// A toolkit that lets jobs be changed, with two of them.
FakeToolkit _writable() => FakeToolkit()
  ..served = {
    ToolkitFeature.memories,
    ToolkitFeature.jobs,
    ToolkitFeature.jobsWrite,
  }
  ..jobs = const [
    ScheduledJob(
      id: '1',
      name: 'Morning brief',
      prompt: 'Give me today in four lines.',
      cron: '0 7 * * *',
      lastStatus: 'completed',
    ),
    ScheduledJob(
      id: '2',
      name: 'Price watch',
      prompt: 'Check the boiler service price.',
      tools: 2,
      cron: '0 */6 * * *',
    ),
  ];

Future<Harness> _open(WidgetTester tester, FakeToolkit toolkit) async {
  final h = await pumpApp(
    tester,
    llm: planningServer(),
    toolkitServer: toolkit,
    shelf: true,
    size: const Size(390, 1000),
  );
  h.shell.openSettings(SettingsPage.upcoming);
  await tester.pumpAndSettle();
  return h;
}

/// The field whose hint is [hint].
Finder _field(String hint) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == hint,
);

const _nameHint = 'Morning brief';
const _promptHint = 'Summarise today: the weather, the bins, anything due.';

/// The UTC cron for a task every day at [hour]:[minute] local time.
String _daily(int hour, int minute) {
  final now = DateTime.now();
  final utc = DateTime(now.year, now.month, now.day, hour, minute).toUtc();
  return '${utc.minute} ${utc.hour} * * *';
}

/// A toolkit whose delete waits for [gate].
class _SlowDelete extends FakeToolkit {
  final gate = Completer<void>();

  @override
  Future<void> deleteJob(String id) async {
    await gate.future;
    await super.deleteJob(id);
  }
}

void main() {
  testWidgets('a toolkit that only lists jobs leaves them read only', (
    tester,
  ) async {
    final toolkit = FakeToolkit()
      ..jobs = const [
        ScheduledJob(id: '1', name: 'Morning brief', cron: '0 7 * * *'),
      ];
    await _open(tester, toolkit);
    expect(find.text('Read only here.'), findsOneWidget);
    expect(control('New task'), findsNothing);
    await tester.tap(find.text('Morning brief'));
    await tester.pumpAndSettle();
    expect(find.text('Run now'), findsNothing);
  });

  testWidgets('a task is added from the plus', (tester) async {
    final toolkit = _writable();
    final h = await _open(tester, toolkit);
    expect(find.text('Times are in your time zone.'), findsOneWidget);
    // AnythingLLM has no task that runs once, nor one tied to a workspace.
    expect(find.text('Once'), findsNothing);
    await tester.tap(control('New task'));
    await tester.pumpAndSettle();
    expect(find.text('New task'), findsOneWidget);
    await tester.enterText(_field(_nameHint), 'Weekly shop');
    await tester.enterText(_field(_promptHint), 'Make the groceries list.');
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    expect(toolkit.calls, contains('createJob:Weekly shop|${_daily(7, 0)}'));
    // The sheet closes and the list has the new task.
    expect(find.text('New task'), findsNothing);
    expect(find.text('Weekly shop'), findsOneWidget);
    expect(h.shell.popup.value, isNull);
  });

  testWidgets(
    'a custom cron that runs too often is refused before it is sent',
    (tester) async {
      final toolkit = _writable();
      await _open(tester, toolkit);
      await tester.tap(control('New task'));
      await tester.pumpAndSettle();
      await tester.enterText(_field(_nameHint), 'Spam');
      await tester.enterText(_field(_promptHint), 'Do it.');
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('0 6 * * 1'), '* * * * *');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('more often than every 5 minutes'),
        findsOneWidget,
      );
      await tester.tap(control('Save'));
      await tester.pumpAndSettle();
      expect(toolkit.calls.where((c) => c.startsWith('createJob')), isEmpty);
      expect(find.text('New task'), findsOneWidget);
    },
  );

  testWidgets('a task needs a name and what it should do', (tester) async {
    final toolkit = _writable();
    await _open(tester, toolkit);
    await tester.tap(control('New task'));
    await tester.pumpAndSettle();
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Give it a name.'), findsOneWidget);
    await tester.enterText(_field(_nameHint), 'Brief');
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Say what it should do.'), findsOneWidget);
    expect(toolkit.calls.where((c) => c.startsWith('createJob')), isEmpty);
  });

  testWidgets('a weekly task needs a day, and sends them as cron days', (
    tester,
  ) async {
    final toolkit = _writable();
    await _open(tester, toolkit);
    await tester.tap(control('New task'));
    await tester.pumpAndSettle();
    await tester.enterText(_field(_nameHint), 'Review');
    await tester.enterText(_field(_promptHint), 'Review the week.');
    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    expect(find.text('Pick at least one day.'), findsOneWidget);
    await tester.tap(control('Monday'));
    await tester.pumpAndSettle();
    await tester.tap(control('Thursday'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Runs on Mondays and Thursdays at 07:00 your time.'),
      findsOneWidget,
    );
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    final sent = toolkit.calls.singleWhere((c) => c.startsWith('createJob'));
    // Minute, hour, then the days, which a zone far from UTC may move by one.
    expect(sent, matches(RegExp(r'\|\d+ \d+ \* \* [0-6](,[0-6])?$')));
  });

  testWidgets(
    'a task opens in its sheet with its runs and Run now starts one',
    (tester) async {
      final toolkit = _writable()
        ..runRecords['1'] = [
          JobRun(
            startedAt: DateTime.now().toUtc(),
            status: 'completed',
            result: 'Done. The answer is in the chat.',
          ),
        ];
      await _open(tester, toolkit);
      await tester.tap(find.text('Morning brief'));
      await tester.pumpAndSettle();
      expect(find.text('Give me today in four lines.'), findsOneWidget);
      expect(find.text('Done. The answer is in the chat.'), findsOneWidget);
      await tester.tap(find.text('Run now'));
      await tester.pumpAndSettle();
      expect(toolkit.calls, contains('runJob:1'));
      expect(toolkit.runRecords['1'], hasLength(2));
    },
  );

  testWidgets('a run that is still going shows Running… until it ends', (
    tester,
  ) async {
    final toolkit = _writable()..runStatus = 'running';
    await _open(tester, toolkit);
    await tester.tap(find.text('Morning brief'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run now'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Running…'), findsWidgets);
    // It ends on the toolkit, and the sheet finds out on its next read.
    toolkit.runRecords['1'] = [
      JobRun(startedAt: DateTime.now().toUtc(), status: 'completed'),
    ];
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Run now'), findsOneWidget);
  });

  testWidgets('a task deleted from another place closes its sheet', (
    tester,
  ) async {
    final toolkit = _writable();
    final h = await _open(tester, toolkit);
    await tester.tap(find.text('Morning brief'));
    await tester.pumpAndSettle();
    expect(h.shell.popup.value, isA<TaskSheet>());
    toolkit.jobs = [toolkit.jobs.last];
    await h.toolkit.readJobs(again: true);
    await tester.pumpAndSettle();
    expect(h.shell.popup.value, isNull);
  });

  testWidgets('a delete that ends after another popup opened leaves it open', (
    tester,
  ) async {
    final toolkit = _SlowDelete()
      ..served = {
        ToolkitFeature.memories,
        ToolkitFeature.jobs,
        ToolkitFeature.jobsWrite,
      }
      ..jobs = _writable().jobs;
    final h = await _open(tester, toolkit);
    await tester.tap(find.text('Morning brief'));
    await tester.pumpAndSettle();
    await tester.tap(control('Delete task'));
    await tester.pumpAndSettle();
    await tester.tap(control('Delete'));
    await tester.pump();
    h.shell.togglePopup(Popup.workspaces);
    toolkit.gate.complete();
    await tester.pumpAndSettle();
    expect(toolkit.calls, contains('deleteJob:1'));
    expect(h.shell.popup.value, Popup.workspaces);
  });

  testWidgets('a run still going is followed again after Edit and Cancel', (
    tester,
  ) async {
    final toolkit = _writable()..runStatus = 'running';
    await _open(tester, toolkit);
    await tester.tap(find.text('Morning brief'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run now'));
    await tester.pump();
    await tester.pump();
    await tester.tap(control('Edit'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(control('Cancel'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Running…'), findsWidgets);
    // It ends on the toolkit, and the sheet finds out on its next read.
    toolkit.runRecords['1'] = [
      JobRun(startedAt: DateTime.now().toUtc(), status: 'completed'),
    ];
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Run now'), findsOneWidget);
  });

  testWidgets('the On switch pauses a task', (tester) async {
    final toolkit = _writable();
    await _open(tester, toolkit);
    await tester.tap(find.text('Morning brief'));
    await tester.pumpAndSettle();
    await tester.tap(control('Task on'));
    await tester.pumpAndSettle();
    expect(toolkit.calls, contains('setJobEnabled:1=false'));
    expect(find.text('Paused'), findsOneWidget);
  });

  testWidgets('Delete asks first, and a task is gone once deleted', (
    tester,
  ) async {
    final toolkit = _writable();
    final h = await _open(tester, toolkit);
    await tester.tap(find.text('Morning brief'));
    await tester.pumpAndSettle();
    await tester.tap(control('Delete task'));
    await tester.pumpAndSettle();
    expect(
      find.text('Delete Morning brief? Its earlier runs go with it.'),
      findsOneWidget,
    );
    await tester.tap(control('Keep'));
    await tester.pumpAndSettle();
    expect(toolkit.calls.where((c) => c.startsWith('deleteJob')), isEmpty);
    await tester.tap(control('Delete task'));
    await tester.pumpAndSettle();
    await tester.tap(control('Delete'));
    await tester.pumpAndSettle();
    expect(toolkit.calls, contains('deleteJob:1'));
    expect(find.text('Morning brief'), findsNothing);
    expect(h.shell.popup.value, isNull);
  });

  testWidgets('a change the toolkit refuses says why, and the sheet stays', (
    tester,
  ) async {
    final toolkit = _writable()
      ..errors['deleteJob'] = const ApiException(
        'The toolkit would not delete it.',
      );
    await _open(tester, toolkit);
    await tester.tap(find.text('Morning brief'));
    await tester.pumpAndSettle();
    await tester.tap(control('Delete task'));
    await tester.pumpAndSettle();
    await tester.tap(control('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Could not delete the task'), findsWidgets);
    expect(find.text('The toolkit would not delete it.'), findsWidgets);
    expect(find.byType(TaskDetail), findsOneWidget);
  });

  testWidgets('why a change failed goes once another task sheet opens', (
    tester,
  ) async {
    final toolkit = _writable()
      ..errors['deleteJob'] = const ApiException(
        'The toolkit would not delete it.',
      );
    final h = await _open(tester, toolkit);
    await tester.tap(find.text('Morning brief'));
    await tester.pumpAndSettle();
    await tester.tap(control('Delete task'));
    await tester.pumpAndSettle();
    await tester.tap(control('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Could not delete the task'), findsWidgets);
    h.shell.closePopup();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Morning brief'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetail), findsOneWidget);
    expect(find.text('Could not delete the task'), findsNothing);
  });

  testWidgets('Edit opens the task as a form and saves it', (tester) async {
    final toolkit = _writable();
    await _open(tester, toolkit);
    await tester.tap(find.text('Morning brief'));
    await tester.pumpAndSettle();
    await tester.tap(control('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit task'), findsOneWidget);
    await tester.enterText(_field(_nameHint), 'Evening brief');
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    expect(
      toolkit.calls.singleWhere((c) => c.startsWith('updateJob')),
      startsWith('updateJob:1|Evening brief|'),
    );
    expect(find.text('Evening brief'), findsOneWidget);
  });

  testWidgets('a task with tools says only the web page sets them', (
    tester,
  ) async {
    await _open(tester, _writable());
    await tester.tap(find.text('Price watch'));
    await tester.pumpAndSettle();
    expect(find.text('Check the boiler service price.'), findsOneWidget);
    expect(
      find.text('May use 2 tools, which only AnythingLLM\'s web page sets.'),
      findsOneWidget,
    );
  });

  testWidgets('Run now on a task AnythingLLM is already running says so', (
    tester,
  ) async {
    final toolkit = _writable()
      ..runRecords['1'] = [
        JobRun(startedAt: DateTime.now().toUtc(), status: 'queued'),
      ];
    await _open(tester, toolkit);
    await tester.tap(find.text('Morning brief'));
    await tester.pumpAndSettle();
    // A run waiting its turn counts as running, so Run now waits too.
    expect(find.text('Running…'), findsWidgets);
    expect(toolkit.calls.where((c) => c.startsWith('runJob')), isEmpty);
  });
}
