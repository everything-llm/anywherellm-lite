import 'package:anywherellm/ui/chat/gallery.dart';
import 'package:flutter/material.dart';
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
      await pumpApp(tester, llm: _searched(8), size: const Size(390, 844));
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
      final h = await pumpApp(
        tester,
        llm: _searched(3),
        size: const Size(390, 844),
      );
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

  testWidgets('a picture that does not load shows its site in its place', (
    tester,
  ) async {
    final llm = _searched(2)
      ..images.remove(Uri.parse('https://h:3001/p/2.jpg'));
    await pumpApp(tester, llm: llm, size: const Size(390, 844));
    expect(
      find.descendant(
        of: find.byType(Gallery),
        matching: find.text('site2.example'),
      ),
      findsOneWidget,
    );
  });
}
