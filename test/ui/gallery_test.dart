import 'package:anywherellm/ui/chat/answer_image.dart';
import 'package:anywherellm/ui/chat/gallery.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pixels.dart';
import '../support/pump.dart';

/// An answer of [count] pictures, each on a line of its own.
FakeAnythingLlm _searched(int count) {
  final llm = answering(
    'These are from the pages I read.\n\n'
    '${[for (var i = 1; i <= count; i++) '[![Unit $i](https://h:3001/p/$i.jpg)](https://site$i.example/p)'].join('\n\n')}',
  );
  for (var i = 1; i <= count; i++) {
    llm.images[Uri.parse('https://h:3001/p/$i.jpg')] = pixel;
  }
  return llm;
}

void main() {
  testWidgets(
    'pictures from a search are one row of four, the last saying how many more',
    (tester) async {
      await pumpApp(tester, llm: _searched(8));
      expect(find.byType(Gallery), findsOneWidget);
      expect(control('Picture 1: Unit 1, from site1.example'), findsOneWidget);
      expect(control('Picture 4 and 4 more'), findsOneWidget);
      expect(find.text('+4'), findsOneWidget);
      // The tiles are square and share one row.
      final first = tester.getRect(
        control('Picture 1: Unit 1, from site1.example'),
      );
      final last = tester.getRect(control('Picture 4 and 4 more'));
      expect(first.width, moreOrLessEquals(first.height));
      expect(last.top, first.top);
    },
  );

  testWidgets(
    'a tile opens the pictures one at a time, with Previous and Next',
    (tester) async {
      final h = await pumpApp(tester, llm: _searched(3));
      await tester.tap(control('Picture 2: Unit 2, from site2.example'));
      await tester.pumpAndSettle();
      expect(find.byType(GalleryPage), findsOneWidget);
      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.text('From this answer'), findsOneWidget);
      expect(find.text('Unit 2'), findsOneWidget);
      expect(find.text('site2.example'), findsOneWidget);
      await tester.tap(control('Next picture'));
      await tester.pumpAndSettle();
      expect(find.text('3 of 3'), findsOneWidget);
      await tester.tap(control('Open page'));
      await tester.pumpAndSettle();
      expect(h.opened.last, Uri.parse('https://site3.example/p'));
      await tester.tap(control('Save'));
      await tester.pumpAndSettle();
      expect(h.saved.keys, contains('3.jpg'));
      await tester.tap(control('Back to the chat'));
      await tester.pumpAndSettle();
      expect(find.byType(GalleryPage), findsNothing);
    },
  );

  testWidgets('Next moves at once when the device asks for less motion', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(tester, llm: _searched(3));
    await tester.tap(control('Picture 2: Unit 2, from site2.example'));
    await tester.pumpAndSettle();
    await tester.tap(control('Next picture'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('3 of 3'), findsOneWidget);
  });

  testWidgets('a lone picture in a link is framed', (tester) async {
    await pumpApp(tester, llm: _searched(1));
    expect(tester.widget<AnswerImage>(find.byType(AnswerImage)).framed, isTrue);
  });

  testWidgets('the gallery page draws its picture without a frame', (
    tester,
  ) async {
    await pumpApp(tester, llm: _searched(3));
    await tester.tap(control('Picture 2: Unit 2, from site2.example'));
    await tester.pumpAndSettle();
    final shown = find.descendant(
      of: find.byType(GalleryPage),
      matching: find.byType(AnswerImage),
    );
    expect(shown, findsWidgets);
    for (final image in tester.widgetList<AnswerImage>(shown)) {
      expect(image.framed, isFalse);
    }
  });

  testWidgets('a picture that does not load shows its site in its place', (
    tester,
  ) async {
    final llm = _searched(2)
      ..images.remove(Uri.parse('https://h:3001/p/2.jpg'));
    await pumpApp(tester, llm: llm);
    expect(
      find.descendant(
        of: find.byType(Gallery),
        matching: find.text('site2.example'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a picture off the server offers no Save or Share and is never read', (
    tester,
  ) async {
    final llm = answering(
      '![a](https://evil.example/a.png)\n\n![b](https://h:3001/p/1.jpg)',
    )..images[Uri.parse('https://h:3001/p/1.jpg')] = pixel;
    await pumpApp(tester, llm: llm, canShare: true);
    await tester.tap(control('Picture 1: a, from evil.example'));
    await tester.pumpAndSettle();
    expect(find.byType(GalleryPage), findsOneWidget);
    expect(control('Open page'), findsOneWidget);
    expect(control('Save'), findsNothing);
    expect(control('Share'), findsNothing);
    expect(
      llm.calls.where((c) => c.startsWith('answerImage:https://evil')),
      isEmpty,
    );
  });

  testWidgets('a picture saves and shares under a name that stays in its folder', (
    tester,
  ) async {
    final traversing = Uri.parse(
      'https://h:3001/x/..%2F..%2Ffiles%2Fprefs.json',
    );
    final llm = answering('![a]($traversing)\n\n![b](https://h:3001/p/1.jpg)')
      ..images[traversing] = pixel
      ..images[Uri.parse('https://h:3001/p/1.jpg')] = pixel;
    final h = await pumpApp(tester, llm: llm, canShare: true);
    await tester.tap(control('Picture 1: a, from h'));
    await tester.pumpAndSettle();
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    await tester.tap(control('Share'));
    await tester.pumpAndSettle();
    expect(h.saved.keys, ['..-..-files-prefs.json']);
    expect(h.shared.keys, ['..-..-files-prefs.json']);
  });

  testWidgets('a picture by a path from the server\'s root saves', (
    tester,
  ) async {
    final llm = answering('![a](/p/1.jpg)\n\n![b](/p/2.jpg)')
      ..images[Uri.parse('https://h:3001/p/1.jpg')] = pixel
      ..images[Uri.parse('https://h:3001/p/2.jpg')] = pixel;
    final h = await pumpApp(tester, llm: llm);
    await tester.tap(control('Picture 1: a, from h'));
    await tester.pumpAndSettle();
    await tester.tap(control('Save'));
    await tester.pumpAndSettle();
    expect(h.saved['1.jpg'], pixel);
  });
}
