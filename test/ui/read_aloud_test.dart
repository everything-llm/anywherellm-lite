import 'package:anywherellm/ui/chat/device_speaker.dart';
import 'package:anywherellm/ui/chat/speaker.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

Finder control(String label) => find.byWidgetPredicate(
  (widget) => widget is Tappable && widget.label == label,
);

void main() {
  testWidgets('there is no Read aloud where the device cannot speak', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer());
    expect(control('Read aloud'), findsNothing);
  });

  testWidgets('Read aloud reads the answer, and Stop reading ends it', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer(), canSpeak: true);
    await tester.tap(control('Read aloud'));
    await tester.pump();
    expect(h.speaker!.spoken, ['About 40k.']);
    expect(control('Stop reading'), findsOneWidget);
    await tester.tap(control('Stop reading'));
    await tester.pump();
    expect(control('Read aloud'), findsOneWidget);
  });

  testWidgets('the button turns back when the reading ends', (tester) async {
    final h = await pumpApp(tester, llm: planningServer(), canSpeak: true);
    await tester.tap(control('Read aloud'));
    await tester.pump();
    h.speaker!.finish();
    await tester.pump();
    await tester.pump();
    expect(control('Read aloud'), findsOneWidget);
  });

  testWidgets('showing another workspace stops the reading', (tester) async {
    final h = await pumpApp(tester, llm: planningServer(), canSpeak: true);
    await tester.tap(control('Read aloud'));
    await tester.pump();
    final stops = h.speaker!.stopped;
    await h.chat.select('household');
    await tester.pumpAndSettle();
    expect(h.speaker!.stopped, stops + 1);
    expect(h.readAloud!.reading, isNull);
  });

  testWidgets('a device that cannot speak says so', (tester) async {
    final h = await pumpApp(tester, llm: planningServer(), canSpeak: true);
    h.speaker!.fails = Exception('No speech engine.');
    await tester.tap(control('Read aloud'));
    await tester.pumpAndSettle();
    expect(find.text('Could not read the answer aloud'), findsOneWidget);
    expect(find.text('No speech engine.'), findsOneWidget);
  });

  test('an answer is read as words, without its markup', () {
    expect(
      plainText(
        '## Budget\n\nAbout **40k**, see [the plan](https://x.example).\n\n'
        '- rent\n- food',
      ),
      'Budget\nAbout 40k, see the plan.\nrent\nfood',
    );
  });

  test('a list item with markup in it is read as one line', () {
    expect(
      plainText('- pay **rent** first\n- then food\n  - nested *item*'),
      'pay rent first\nthen food\nnested item',
    );
  });

  test('a long answer is read in pieces cut between sentences', () {
    final sentence = 'This is one sentence. ';
    final parts = speechParts(sentence * 300, most: 1000);
    expect(parts.every((p) => p.length <= 1000), isTrue);
    expect(parts.every((p) => p.endsWith('.')), isTrue);
    expect(parts.join(' '), (sentence * 300).trim());
  });
}
