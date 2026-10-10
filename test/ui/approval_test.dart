import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/errors.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

ApprovalRequest asking({
  String id = 'q1',
  Duration within = const Duration(minutes: 2),
}) => ApprovalRequest(
  runId: 'r_1',
  id: id,
  skill: 'create-text-file',
  description: 'Write hello.txt',
  payload: const {'filename': 'hello.txt'},
  expires: DateTime.now().add(within),
);

void main() {
  Future<FakeAnythingLlm> waiting(WidgetTester tester) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('Write hello.txt');
    await tester.pump();
    llm.chat!.add(asking());
    await tester.pump();
    return llm;
  }

  testWidgets('a tool that needs approval asks, in words', (tester) async {
    await waiting(tester);
    expect(find.text('Allow create-text-file?'), findsOneWidget);
    expect(find.textContaining('Write hello.txt'), findsWidgets);
    expect(control('Allow'), findsOneWidget);
    expect(control('Deny'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Allow tells the server and takes the question away', (
    tester,
  ) async {
    final llm = await waiting(tester);
    await tester.tap(control('Allow'));
    await tester.pump();
    expect(llm.calls, contains('answerApproval:q1:allow'));
    expect(find.text('Allow create-text-file?'), findsNothing);
  });

  testWidgets('Deny tells the server it was refused', (tester) async {
    final llm = await waiting(tester);
    await tester.tap(control('Deny'));
    await tester.pump();
    expect(llm.calls, contains('answerApproval:q1:deny'));
  });

  testWidgets('the arguments show on request', (tester) async {
    await waiting(tester);
    expect(find.textContaining('"filename"'), findsNothing);
    await tester.tap(control('Show details'));
    await tester.pump();
    expect(find.textContaining('"filename": "hello.txt"'), findsOneWidget);
  });

  testWidgets('an answer given elsewhere takes the question away', (
    tester,
  ) async {
    final llm = await waiting(tester);
    llm.chat!.add(const ApprovalSettled('q1'));
    await tester.pump();
    expect(find.text('Allow create-text-file?'), findsNothing);
  });

  testWidgets('a server that cannot be told puts the question back', (
    tester,
  ) async {
    final llm = await waiting(tester);
    llm.errors['answerApproval'] = const ApiException('Relay is down.');
    await tester.tap(control('Allow'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Allow create-text-file?'), findsOneWidget);
    expect(find.textContaining('Relay is down.'), findsOneWidget);
  });

  testWidgets('a question already answered or timed out is not put back', (
    tester,
  ) async {
    final llm = await waiting(tester);
    llm.errors['answerApproval'] = const ApiException(
      'That approval was answered already.',
      status: 409,
    );
    await tester.tap(control('Allow'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Allow create-text-file?'), findsNothing);
  });

  testWidgets('a request past its time asks nothing', (tester) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('Write hello.txt');
    await tester.pump();
    llm.chat!.add(asking(within: const Duration(seconds: -1)));
    await tester.pump();
    expect(find.text('Not answered in time'), findsOneWidget);
    expect(control('Allow'), findsNothing);
  });

  testWidgets('the answer ending clears what it was waiting for', (
    tester,
  ) async {
    final llm = await waiting(tester);
    llm.chat!
      ..add(const TextChunk('Done without it.'))
      ..add(const ChatDone([]));
    await llm.chat!.close();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Allow create-text-file?'), findsNothing);
  });

  for (final width in [360.0, 1400.0]) {
    testWidgets('the question fits at $width', (tester) async {
      final llm = planningServer()..hold = true;
      final h = await pumpApp(tester, llm: llm, size: Size(width, 700));
      await h.chat.send('Write hello.txt');
      await tester.pump();
      llm.chat!.add(
        ApprovalRequest(
          runId: 'r_1',
          id: 'q1',
          skill: 'create-text-file-${'x' * 80}',
          description: 'Write ${'a' * 120}.txt',
          payload: {'filename': 'a' * 200},
          expires: DateTime.now().add(const Duration(minutes: 2)),
        ),
      );
      await tester.pump();
      await tester.tap(control('Show details'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
