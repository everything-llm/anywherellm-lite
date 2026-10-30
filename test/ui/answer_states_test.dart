import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/ui/chat/answer_body.dart';
import 'package:anywherellm/ui/widgets/sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// Whether the answer that shows [text] is drawn in the second ink.
bool muted(WidgetTester tester, String text) => tester
    .widget<AnswerBody>(
      find.byWidgetPredicate((w) => w is AnswerBody && w.text == text),
    )
    .muted;

void main() {
  testWidgets('Stop is named for what it stops', (tester) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('And next quarter?');
    await tester.pump();
    expect(find.byTooltip('Stop the answer'), findsOneWidget);
  });

  testWidgets('a stopped answer keeps Retry and its text in the second ink', (
    tester,
  ) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('And next quarter?');
    await tester.pump();
    llm.chat!.add(const TextChunk('Next quarter we'));
    await tester.pump();
    expect(muted(tester, 'Next quarter we'), isFalse);
    h.chat.stop();
    await tester.pump(const Duration(milliseconds: 300));
    expect(muted(tester, 'Next quarter we'), isTrue);
    await tester.tap(control('More: read aloud, ask again, details'));
    await tester.pumpAndSettle();
    expect(control('Ask again'), findsOneWidget);
  });

  testWidgets('a failed answer asks again in its box, not twice', (
    tester,
  ) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('And next quarter?');
    await tester.pump();
    llm.chat!
      ..add(const TextChunk('Next quarter we'))
      ..addError(const ApiException('The server stopped the answer.'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ask again'), findsOneWidget);
    await tester.tap(control('More: read aloud, ask again, details'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(SheetFrame),
        matching: control('Ask again'),
      ),
      findsNothing,
      reason: 'the box asks again',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    // The chat's earlier answer shows its own Copy only once tapped.
    expect(control('Copy answer'), findsOneWidget);
    expect(muted(tester, 'Next quarter we'), isTrue);
  });
}
