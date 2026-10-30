import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/widgets/sheet.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets(
    "a phone's sources fold into +N, which lists them by site in a sheet",
    (tester) async {
      final llm = planningServer()..hold = true;
      final h = await pumpApp(tester, llm: llm);
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
      // A web page's chip names its site; those that don't fit with a readable name fold into
      // +N, which counts every one not shown.
      expect(find.text('site1.example'), findsOneWidget);
      expect(find.text('site4.example'), findsNothing);
      final shown = [
        for (var i = 1; i <= 7; i++)
          if (find.text('site$i.example').evaluate().isNotEmpty) i,
      ];
      expect(shown, [for (var i = 1; i <= shown.length; i++) i]);
      await tester.tap(control('${7 - shown.length} more sources. Show all 7'));
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

  testWidgets('the sheet follows the documents read while it shows', (
    tester,
  ) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await h.chat.send('What do we know?');
    await tester.pump();
    llm.chat!
      ..add(const WholeAnswer('A few things.'))
      ..add(
        const ChatDone([
          Citation('Q3 roadmap.pdf'),
          Citation('Notes a'),
          Citation('Notes b'),
          Citation('Notes c'),
          Citation('Notes d'),
        ]),
      );
    await llm.chat!.close();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Tappable && w.label.contains('more sources'),
      ),
    );
    await tester.pumpAndSettle();
    expect(control('Q3 roadmap.pdf, In Documents'), findsOneWidget);
    llm.spaces[0].docs.removeWhere((d) => d.title == 'Q3 roadmap.pdf');
    await h.sources.refresh();
    await tester.pumpAndSettle();
    expect(control('Q3 roadmap.pdf, In Documents'), findsNothing);
    expect(control('Q3 roadmap.pdf'), findsOneWidget);
  });
}
