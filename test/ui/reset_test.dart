import 'package:anywherellm/core/errors.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// Types `/reset` and sends it.
Future<void> askReset(WidgetTester tester) async {
  await tester.enterText(composerField, '/reset');
  await tester.pump();
  await tester.tap(control('Send'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('/reset asks first, then clears the chat on the server', (
    tester,
  ) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    final thread = h.chat.activeThread!;
    expect(h.chat.turns, isNotEmpty);

    await askReset(tester);
    expect(find.textContaining('Clear this chat?'), findsOneWidget);
    expect(llm.calls, isNot(contains('resetChat:$thread')));

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('resetChat:$thread'));
    expect(h.chat.turns, isEmpty);
    expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
    expect(find.textContaining('Clear this chat?'), findsNothing);
  });

  testWidgets('Keep leaves the chat as it is', (tester) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    final turns = h.chat.turns.length;

    await askReset(tester);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(llm.calls.where((c) => c.startsWith('resetChat')), isEmpty);
    expect(h.chat.turns.length, turns);
  });

  testWidgets('a message sent instead of an answer puts the question away', (
    tester,
  ) async {
    final llm = planningServer();
    await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();

    await askReset(tester);
    expect(find.textContaining('Clear this chat?'), findsOneWidget);
    await tester.enterText(composerField, 'And next quarter?');
    await tester.pump();
    await tester.tap(control('Send'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('streamChat:budget:And next quarter?'));
    expect(find.textContaining('Clear this chat?'), findsNothing);
  });

  testWidgets('typing a slash lists /reset, and Enter on it asks', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer());
    await tester.pumpAndSettle();

    await tester.enterText(composerField, '/res');
    await tester.pump();
    expect(find.text('Clear this chat'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.textContaining('Clear this chat?'), findsOneWidget);
  });

  testWidgets('a draft has nothing to clear, so /reset is sent as typed', (
    tester,
  ) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm);
    h.chat.newChat();
    await tester.pumpAndSettle();

    await tester.enterText(composerField, '/res');
    await tester.pump();
    expect(find.text('Clear this chat'), findsNothing);
    await tester.enterText(composerField, '/reset');
    await tester.pump();
    await tester.tap(control('Send'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('streamChat:th-1:/reset'));
  });

  testWidgets('a clear the server refuses keeps the turns and says why', (
    tester,
  ) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    final turns = h.chat.turns.length;
    llm.errors['resetChat'] = ApiException('No.', status: 500);

    await h.chat.reset();
    await tester.pumpAndSettle();
    expect(h.chat.turns.length, turns);
    expect(h.chat.problem?.title, 'Could not clear the chat');
    expect(h.chat.busy, isFalse);
  });
}
