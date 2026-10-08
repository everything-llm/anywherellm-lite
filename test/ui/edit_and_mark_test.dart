import 'package:anywherellm/core/ports.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Edit shows that sending replaces the message, and Send as new '
      'stops that', (tester) async {
    await pumpApp(tester, llm: withChatIds());
    await tester.tap(control('Edit'));
    await tester.pump();
    expect(find.textContaining('Editing a sent message'), findsOneWidget);
    await tester.tap(control('Send as new'));
    await tester.pump();
    expect(find.textContaining('Editing a sent message'), findsNothing);
    expect(composerText(tester), 'What is the budget?');
  });

  testWidgets('an edit whose old exchange cannot be deleted stays in the '
      'composer', (tester) async {
    final llm = withChatIds()
      ..errors['dropFrom'] = const ApiException('no', status: 500);
    await pumpApp(tester, llm: llm);
    await tester.tap(control('Edit'));
    await tester.pump();
    await tester.enterText(composerField, 'What is the Q3 budget?');
    await tester.pump();
    await tester.tap(control('Send'));
    await tester.pumpAndSettle();
    expect(composerText(tester), 'What is the Q3 budget?');
    expect(find.textContaining('Editing a sent message'), findsOneWidget);
    expect(find.text('Could not replace the old exchange'), findsOneWidget);
    expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
  });

  testWidgets('thumbs in More mark an answer, a second tap clears it, and a '
      'refusal puts it back', (tester) async {
    final llm = withChatIds();
    await pumpApp(tester, llm: llm);
    expect(find.byTooltip('Good answer'), findsNothing);
    await tester.tap(control('More for this answer'));
    await tester.pumpAndSettle();
    expect(find.text('Rate this answer'), findsOneWidget);
    await tester.tap(find.byTooltip('Good answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Good answer'));
    await tester.pumpAndSettle();
    expect(llm.calls.where((c) => c.startsWith('setFeedback')), [
      'setFeedback:5:true',
      'setFeedback:5:null',
    ]);
    llm.errors['setFeedback'] = const ApiException('no', status: 500);
    await tester.tap(find.byTooltip('Bad answer'));
    await tester.pumpAndSettle();
    expect(find.text('Could not mark the answer'), findsOneWidget);
  });

  testWidgets('Retry says why it is off for a question sent with files', (
    tester,
  ) async {
    await pumpApp(tester, llm: withChatIds(attachments: ['photo.png']));
    expect(
      find.byTooltip(
        'Retry is off: the files sent with the question are not kept',
      ),
      findsOneWidget,
    );
  });
}
