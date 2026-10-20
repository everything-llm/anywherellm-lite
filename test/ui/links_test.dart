import 'dart:async';

import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/chat/browser_sheet.dart';
import 'package:anywherellm/ui/chat/page_sheet.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/state/notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
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
    final page = Uri.parse(
      'https://h:3001/apps-lean/q9Zx_-1aB2.html?theme=light',
    );
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

  group('a comment from an app\'s page', () {
    String comment(String workspace) =>
        '{"comment":{"workspace":"$workspace",'
        '"message":"About my Groceries page: bigger buttons?"}}';

    Future<Harness> opened(WidgetTester tester, FakeAnythingLlm llm) async {
      final h = await pumpApp(tester, llm: llm, canViewApps: true);
      await tapLink(tester, 'Groceries');
      await tester.pumpAndSettle();
      return h;
    }

    /// The comment's question over the page.
    Finder asking() => find.textContaining('Send this to the chat?');

    testWidgets('asks first, then goes in the chat as the person\'s message, '
        'and the page closes so the answer shows', (tester) async {
      final llm = answering('Made it: [Groceries](/apps-lean/q9Zx_-1aB2.html)');
      final h = await opened(tester, llm);
      h.appView!.channel!.onMessage(comment('q3'));
      await tester.pumpAndSettle();
      expect(asking(), findsOneWidget);
      expect(
        find.textContaining('About my Groceries page: bigger buttons?'),
        findsOneWidget,
      );
      expect(
        llm.calls.where((c) => c.startsWith('streamChat')),
        isEmpty,
        reason: 'a page can post without the person, so nothing goes unasked',
      );
      expect(h.appView!.ran, isEmpty);
      await tester.tap(asked('Send'));
      await tester.pumpAndSettle();
      expect(
        llm.calls.last,
        'streamChat:budget:About my Groceries page: bigger buttons?',
      );
      expect(h.appView!.ran.single, contains('{"ok":true}'));
      expect(find.byType(PageSheet), findsNothing);
    });

    testWidgets('Cancel sends nothing and tells the page', (tester) async {
      final llm = answering('Made it: [Groceries](/apps-lean/q9Zx_-1aB2.html)');
      final h = await opened(tester, llm);
      h.appView!.channel!.onMessage(comment('q3'));
      await tester.pumpAndSettle();
      await tester.tap(asked('Cancel'));
      await tester.pumpAndSettle();
      expect(asking(), findsNothing);
      expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
      expect(h.appView!.ran.single, contains('"ok":false'));
      expect(h.appView!.ran.single, contains('Not sent.'));
      expect(find.byType(PageSheet), findsOneWidget);
    });

    testWidgets('Esc closes the page, and the comment goes unsent', (
      tester,
    ) async {
      final llm = answering('Made it: [Groceries](/apps-lean/q9Zx_-1aB2.html)');
      final h = await opened(tester, llm);
      h.appView!.channel!.onMessage(comment('q3'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(asking(), findsNothing);
      expect(find.byType(PageSheet), findsNothing);
      expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
    });

    testWidgets('one posted while another waits is refused', (tester) async {
      final llm = answering('Made it: [Groceries](/apps-lean/q9Zx_-1aB2.html)');
      final h = await opened(tester, llm);
      h.appView!.channel!.onMessage(comment('q3'));
      await tester.pumpAndSettle();
      h.appView!.channel!.onMessage(comment('q3'));
      await tester.pumpAndSettle();
      expect(asking(), findsOneWidget);
      expect(h.appView!.ran.single, contains('Another comment is waiting.'));
    });

    testWidgets('on an app of another workspace stays on the page, which '
        'says why', (tester) async {
      final llm = answering('Made it: [Groceries](/apps-lean/q9Zx_-1aB2.html)');
      final h = await opened(tester, llm);
      h.appView!.channel!.onMessage(comment('household'));
      await tester.pumpAndSettle();
      expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
      expect(h.appView!.ran.single, contains('another workspace'));
      expect(find.byType(PageSheet), findsOneWidget);
    });

    testWidgets('while the chat answers stays on the page, which says why', (
      tester,
    ) async {
      final llm = answering('Made it: [Groceries](/apps-lean/q9Zx_-1aB2.html)')
        ..hold = true;
      final h = await opened(tester, llm);
      await h.chat.send('Anything else?');
      await tester.pump();
      h.appView!.channel!.onMessage(comment('q3'));
      // The answer's caret never settles, so the question is given time to rise.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(asked('Send'));
      await tester.pump();
      await tester.pump();
      expect(h.appView!.ran.single, contains('try again once it’s free'));
      expect(find.byType(PageSheet), findsOneWidget);
    });
  });

  testWidgets('an app\'s page opens in the theme the app shows in', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      llm: answering('Made it: [Groceries](/apps-lean/q9Zx_-1aB2.html)'),
      prefsStore: FakePrefsStore(const Prefs(theme: ThemePref.dark)),
      canViewApps: true,
    );
    await tapLink(tester, 'Groceries');
    await tester.pumpAndSettle();
    expect(h.appView!.shown.single.queryParameters, {'theme': 'dark'});
  });

  testWidgets('an app\'s page follows the device while the theme is System', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final h = await pumpApp(
      tester,
      llm: answering('Made it: [Groceries](/apps-lean/q9Zx_-1aB2.html)'),
      canViewApps: true,
    );
    await tapLink(tester, 'Groceries');
    await tester.pumpAndSettle();
    expect(h.appView!.shown.single.queryParameters, {'theme': 'dark'});
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

  group('the Library page', () {
    const answer = 'Enter it on [the Library page](/library-lean/aB3_-x9.html)';
    final page = Uri.parse('https://h:3001/library-lean/aB3_-x9.html');

    testWidgets('opens in a sheet over the chat', (tester) async {
      final h = await pumpApp(
        tester,
        llm: answering(answer),
        canViewApps: true,
      );
      await tapLink(tester, 'the Library page');
      await tester.pumpAndSettle();
      expect(h.shell.popup.value, isA<PageOpen>());
      expect(find.text('Web view of $page'), findsOneWidget);
      expect(h.opened, isEmpty);
      h.appView!.close!();
      await tester.pumpAndSettle();
      expect(find.byType(PageSheet), findsNothing);
    });

    testWidgets('opens in the browser without a web view', (tester) async {
      final h = await pumpApp(tester, llm: answering(answer));
      await tapLink(tester, 'the Library page');
      expect(h.opened, [page]);
    });
  });

  testWidgets('the Vault opens in a sheet over the chat, in the app\'s theme', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      llm: answering('Enter it on [the Vault](/vault-lean/aB3_-x9.html)'),
      canViewApps: true,
    );
    await tapLink(tester, 'the Vault');
    await tester.pumpAndSettle();
    expect(h.shell.popup.value, isA<PageOpen>());
    expect(
      find.text(
        'Web view of https://h:3001/vault-lean/aB3_-x9.html?theme=light',
      ),
      findsOneWidget,
    );
    expect(h.opened, isEmpty);
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

  testWidgets('a message the bar cannot send after the hand back stays typed', (
    tester,
  ) async {
    final llm = answering('Done: [the tab](/browser-lean/3kQ.html)');
    final h = await pumpApp(tester, llm: llm, canViewApps: true);
    await tapLink(tester, 'the tab');
    await tester.pumpAndSettle();
    final page = h.appView!.channel!;
    page.onMessage('{"who":"user"}');
    await tester.pumpAndSettle();
    final bar = find.descendant(
      of: find.byType(AgentBar),
      matching: find.byType(EditableText),
    );
    await tester.enterText(bar, 'Book Tuesday');
    await tester.pump();
    await tester.tap(control('Send to the agent'));
    await tester.pump();
    // The workspace starts answering while the tab is handed back.
    llm.hold = true;
    unawaited(h.chat.send('Something else'));
    await tester.pump();
    page.onMessage('{"gave":true}');
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<EditableText>(bar).controller.text, 'Book Tuesday');
    await llm.chat!.close();
    await tester.pump(const Duration(seconds: 1));
  });
}
