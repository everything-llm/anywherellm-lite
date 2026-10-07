import 'package:anywherellm/ui/chat/message_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// How far the chat is scrolled up from its newest turn.
double _scrolledUp(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(MessageList),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position
    .pixels;

/// An answer long enough to scroll.
final _long = [for (var i = 1; i <= 80; i++) 'Line $i.'].join('\n\n');

/// Scrolls the chat up, away from its newest turn.
Future<void> _scrollUp(WidgetTester tester) async {
  await tester.drag(find.byType(MessageList), const Offset(0, 400));
  await tester.pumpAndSettle();
  expect(_scrolledUp(tester), greaterThan(0));
}

void main() {
  testWidgets('sending while scrolled up brings the new question into view', (
    tester,
  ) async {
    final llm = answering(_long)..hold = true;
    await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    await _scrollUp(tester);

    await tester.enterText(composerField, 'And then?');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(_scrolledUp(tester), 0);
    expect(find.text('And then?'), findsOneWidget);
  });

  testWidgets('another chat opens at its newest turn', (tester) async {
    final llm = answering(_long);
    final h = await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    await _scrollUp(tester);
    llm.histories['priorities'] = [...llm.histories['budget']!];
    await h.chat.open('priorities');
    await tester.pumpAndSettle();
    expect(_scrolledUp(tester), 0);
  });
}
