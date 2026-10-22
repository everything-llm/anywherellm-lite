import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/chat/citation_fit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  group('fitChips', () {
    test('all fit at their natural width when there is room', () {
      final widths = fitChips(
        readable: [80, 80],
        natural: [120, 100],
        count: 2,
        more: 44,
        width: 400,
        gap: 6,
      );
      expect(widths, [120, 100]);
    });

    test('the room left is shared out, none past its natural width', () {
      final widths = fitChips(
        readable: [80, 80, 80],
        natural: [140, 90, 140],
        count: 4,
        more: 44,
        width: 80 * 3 + 12 + 6 + 44 + 40,
        gap: 6,
      );
      expect(widths, hasLength(3));
      expect(widths[1], 90);
      expect(widths[0], closeTo(95, 0.01));
      expect(widths[2], closeTo(95, 0.01));
    });

    test('a chip that cannot have its readable width folds into +N', () {
      final widths = fitChips(
        readable: [120, 120, 120],
        natural: [140, 140, 140],
        count: 5,
        more: 44,
        width: 358,
        gap: 6,
      );
      expect(widths, hasLength(2));
      for (final w in widths) {
        expect(w, greaterThanOrEqualTo(120));
      }
    });

    test('with room for none, only +N shows', () {
      final widths = fitChips(
        readable: [200, 200],
        natural: [200, 200],
        count: 2,
        more: 44,
        width: 150,
        gap: 6,
      );
      expect(widths, isEmpty);
    });
  });

  testWidgets('a chip measured to fit its whole name draws it whole: the measure and the chip '
      'agree', (tester) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm, size: const Size(600, 844));
    await h.chat.send('Where?');
    await tester.pump();
    llm.chat!
      ..add(const WholeAnswer('Here.'))
      ..add(
        ChatDone([
          for (var i = 1; i <= 6; i++)
            Citation('Page $i', url: Uri.https('s$i.ex', '/p')),
        ]),
      );
    await llm.chat!.close();
    await tester.pumpAndSettle();
    for (final i in [1, 2, 3]) {
      final name = tester.renderObject<RenderParagraph>(
        find
            .descendant(
              of: control('Source $i: Page $i, opens in the browser'),
              matching: find.byType(RichText),
            )
            .last,
      );
      expect(name.didExceedMaxLines, isFalse, reason: 'chip $i');
    }
    final more = tester.renderObject<RenderParagraph>(
      find
          .descendant(
            of: control('3 more sources'),
            matching: find.byType(RichText),
          )
          .last,
    );
    expect(more.didExceedMaxLines, isFalse);
  });

  // Long site names, as an agent's web research brings back.
  String site(int i) => 'interview-notes-$i.example.com';

  for (final count in [1, 4, 5, 131]) {
    for (final width in [390.0, 320.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$count sources at $width wide, text at ${scale}x: each chip shown reads at least '
          '8 characters, and +N counts the rest',
          (tester) async {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            final llm = planningServer()..hold = true;
            final h = await pumpApp(tester, llm: llm, size: Size(width, 844));
            await h.chat.send('Who sells interview incentives?');
            await tester.pump();
            llm.chat!
              ..add(const WholeAnswer('Several do.'))
              ..add(
                ChatDone([
                  for (var i = 1; i <= count; i++)
                    Citation('Page $i', url: Uri.https(site(i), '/p')),
                ]),
              );
            await llm.chat!.close();
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            Finder chip(int i) =>
                control('Source $i: Page $i, opens in the browser');
            final shown = [
              for (var i = 1; i <= count; i++)
                if (chip(i).evaluate().isNotEmpty) i,
            ];
            expect(shown, [for (var i = 1; i <= shown.length; i++) i]);
            final folded = count - shown.length;
            if (folded > 0) {
              // The sample chat's earlier answer may fold into a chip of the same count.
              expect(control('$folded more sources'), findsWidgets);
            } else {
              expect(find.textContaining(RegExp(r'^\+\d')), findsNothing);
            }

            for (final i in shown) {
              final name = tester.renderObject<RenderParagraph>(
                find
                    .descendant(of: chip(i), matching: find.byType(RichText))
                    .last,
              );
              final eight = TextPainter(
                text: TextSpan(
                  text: site(i).substring(0, 8),
                  style: name.text.style,
                ),
                textDirection: TextDirection.ltr,
                textScaler: name.textScaler,
                maxLines: 1,
              )..layout();
              expect(
                name.size.width,
                greaterThanOrEqualTo(eight.width),
                reason: 'chip $i shows at least 8 characters',
              );
              eight.dispose();
            }
          },
        );
      }
    }
  }
}
