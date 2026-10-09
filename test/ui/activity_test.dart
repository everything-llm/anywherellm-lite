import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/activity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

const phone = Size(390, 844);

RelayRun run(
  String id,
  String thread,
  String status, {
  String workspace = 'q3',
  String? question,
  String? error,
  Duration startedAgo = const Duration(minutes: 5),
  Duration? finishedAgo,
}) {
  final now = DateTime.now().toUtc();
  return RelayRun(
    id: id,
    workspace: workspace,
    thread: thread,
    status: status,
    question: question,
    error: error,
    started: now.subtract(startedAgo),
    finished: finishedAgo == null ? null : now.subtract(finishedAgo),
  );
}

FakeAnythingLlm server() => planningServer()
  ..allRuns = [
    run(
      'r1',
      'priorities',
      'running',
      question: 'Draft an agenda for the kickoff.',
      startedAgo: const Duration(minutes: 3),
    ),
    run(
      'r2',
      'budget',
      'done',
      question: 'What is the budget?',
      finishedAgo: const Duration(minutes: 12),
    ),
    run(
      'r3',
      'budget',
      'failed',
      question: 'When is the service due?',
      error: 'The relay restarted during the answer.',
      startedAgo: const Duration(days: 1, hours: 2),
      finishedAgo: const Duration(days: 1, hours: 1),
    ),
    run(
      'r4',
      'gone',
      'cancelled',
      question: 'Research recruiting.',
      startedAgo: const Duration(days: 3),
      finishedAgo: const Duration(days: 2, hours: 1),
    ),
  ];

void main() {
  testWidgets('the phone\'s drawer counts what is running and opens Activity', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: server(), size: phone);
    h.shell.toggleSide();
    await tester.pumpAndSettle();
    expect(control('Activity, 1 running'), findsOneWidget);
    expect(find.text('1 running'), findsOneWidget);
    await tester.tap(control('Activity, 1 running'));
    await tester.pumpAndSettle();
    expect(find.byType(ActivityPage), findsOneWidget);
    expect(find.text('RUNNING NOW'), findsOneWidget);
    expect(find.text('FINISHED, LAST 7 DAYS'), findsOneWidget);
    expect(find.text('Q3 planning · Quarter priorities'), findsOneWidget);
    expect(find.text('Draft an agenda for the kickoff.'), findsOneWidget);
    expect(find.textContaining('Answering'), findsOneWidget);
    expect(find.textContaining('Done · 12 min ago'), findsOneWidget);
    expect(find.textContaining('Failed · yesterday'), findsOneWidget);
    expect(find.text('The relay restarted during the answer.'), findsOneWidget);
    expect(find.textContaining('Stopped · 2 days ago'), findsOneWidget);
    expect(find.text('Q3 planning · A chat that is gone'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.shell.activityOpen, isFalse);
  });

  testWidgets('Stop ends a running answer and the row says Stopped', (
    tester,
  ) async {
    final llm = server();
    final h = await pumpApp(tester, llm: llm, size: phone);
    h.shell.openActivity();
    await tester.pumpAndSettle();
    await tester.tap(control('Stop this answer'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('cancelRun:r1'));
    expect(control('Stop this answer'), findsNothing);
    expect(find.text('RUNNING NOW'), findsNothing);
    expect(find.textContaining('Stopped'), findsNWidgets(2));
  });

  testWidgets('a finished row opens its chat', (tester) async {
    final h = await pumpApp(tester, llm: server(), size: phone);
    h.shell.openActivity();
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ActivityPage),
        matching: find.text('What is the budget?'),
      ),
    );
    await tester.pumpAndSettle();
    expect(h.shell.activityOpen, isFalse);
    expect(h.chat.activeThread, 'budget');
  });

  testWidgets('a server with no relay says so and offers the list again', (
    tester,
  ) async {
    final llm = server()
      ..errors['relayRuns'] = const ApiException(
        'This server has no everythingllm relay, so it keeps no list of answers.',
      );
    final h = await pumpApp(tester, llm: llm, size: phone);
    h.shell.openActivity();
    await tester.pumpAndSettle();
    expect(find.textContaining('no everythingllm relay'), findsOneWidget);
    expect(find.text('RUNNING NOW'), findsNothing);
    llm.errors.remove('relayRuns');
    await tester.tap(control('Read the list again'));
    await tester.pumpAndSettle();
    expect(find.text('RUNNING NOW'), findsOneWidget);
  });

  testWidgets('long unbroken words overflow nothing on the narrowest phone', (
    tester,
  ) async {
    final long = 'x' * 200;
    final llm = server()
      ..allRuns = [
        run('r1', 'priorities', 'running', question: long),
        run(
          'r2',
          'budget',
          'failed',
          question: long,
          error: long,
          finishedAgo: const Duration(hours: 3),
        ),
      ];
    final h = await pumpApp(tester, llm: llm, size: const Size(360, 480));
    h.shell.openActivity();
    await tester.pumpAndSettle();
    expect(find.byType(ActivityPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a desktop has no Activity in the sidebar', (tester) async {
    await pumpApp(tester, llm: server());
    expect(find.text('Activity'), findsNothing);
  });
}
