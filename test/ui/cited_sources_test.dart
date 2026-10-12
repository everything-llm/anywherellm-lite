import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/widgets/sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets(
    "a phone's sources fold into +N, which lists them by site in a sheet",
    (tester) async {
      final llm = planningServer()..hold = true;
      final h = await pumpApp(tester, llm: llm, size: const Size(390, 844));
      await h.chat.send('How do teams recruit?');
      await tester.pump();
      llm.chat!
        ..add(const WholeAnswer('Four routes come up most often.'))
        ..add(
          ChatDone([
            for (var i = 1; i <= 7; i++)
              Citation('Page $i', url: Uri.parse('https://site$i.example/p')),
          ]),
        );
      await llm.chat!.close();
      await tester.pumpAndSettle();
      // A web page's chip names its site.
      expect(find.text('site1.example'), findsOneWidget);
      expect(find.text('site4.example'), findsNothing);
      await tester.tap(control('4 more sources'));
      await tester.pumpAndSettle();
      final sheet = find.byType(SheetFrame);
      expect(
        find.descendant(of: sheet, matching: find.text('Sources')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sheet,
          matching: find.text('7 web pages the agent read.'),
        ),
        findsOneWidget,
      );
      await tester.tap(control('Page 6, site6.example'));
      await tester.pumpAndSettle();
      expect(h.opened.last, Uri.parse('https://site6.example/p'));
    },
  );
}
