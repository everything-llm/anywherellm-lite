import 'package:anywherellm/core/browser.dart';
import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pixels.dart';
import '../support/pump.dart';

const _page = 'https://h:8445/_live/browser/bw-3aeecef2b460eeb7';

BrowserTab _tab(String state) => BrowserTab(
  card: Uri.parse('$_page.jpg'),
  page: Uri.parse(_page),
  frame: Uri.parse('https://h:8445/_live/browser/chat/q3/budget/card.jpg'),
  state: state,
  title: 'Hacker News',
  site: 'ycombinator.com',
  last: 'Opened the front page',
);

/// A server whose open chat, `budget`, has a browser tab in [state].
FakeAnythingLlm _server(String state) => planningServer()
  ..browsers['budget'] = ChatBrowser(tab: _tab(state))
  ..frames['budget'] = pixel;

/// Closes the panel, which lets go of the picture it reads.
Future<void> _close(WidgetTester tester, Harness h) async {
  h.shell.closeBrowser();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets(
    'a chat the server says has a browser shows Browser, and the tab',
    (tester) async {
      final h = await pumpApp(tester, llm: _server('idle'));
      await tester.pump(const Duration(milliseconds: 50));
      // No answer here used it, yet the server says the chat has a tab.
      expect(control('Browser'), findsOneWidget);
      await tester.tap(control('Browser'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(h.shell.browserOpen, isTrue);
      expect(
        find.text('The agent has it but is not using it now.'),
        findsOneWidget,
      );
      expect(find.text('Hacker News'), findsOneWidget);
      expect(find.text('ycombinator.com'), findsOneWidget);
      expect(find.text('Last: Opened the front page'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(control('Take over'));
      await tester.pump();
      expect(h.opened, [Uri.parse(_page)]);
      expect(find.text('Hand back to the agent'), findsNothing);
    },
  );

  testWidgets('a chat the server knows no browser of has no Browser', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer());
    await tester.pump(const Duration(milliseconds: 50));
    expect(control('Browser'), findsNothing);
  });

  testWidgets('the person\'s browser is handed back to the agent', (
    tester,
  ) async {
    final llm = _server('user');
    final h = await pumpApp(tester, llm: llm);
    h.shell.showBrowser();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('You have the browser.'), findsOneWidget);
    expect(control('Take over'), findsNothing);
    expect(
      find.text('The agent cannot act while you have it.'),
      findsOneWidget,
    );
    await tester.tap(control('Hand back to the agent'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(llm.calls, contains('handBackBrowser:budget'));
    expect(
      find.text('The agent has it but is not using it now.'),
      findsOneWidget,
    );
    expect(control('Take over'), findsOneWidget);
    expect(control('Hand back to the agent'), findsNothing);
  });

  testWidgets('a hand back the server refuses says why', (tester) async {
    final llm = _server('user')
      ..errors['handBackBrowser'] = const ApiException(
        'This chat has no browser tab.',
      );
    final h = await pumpApp(tester, llm: llm);
    h.shell.showBrowser();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(control('Hand back to the agent'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Could not hand the browser back'), findsOneWidget);
    expect(find.text('This chat has no browser tab.'), findsOneWidget);
    expect(control('Hand back to the agent'), findsOneWidget);
  });

  testWidgets('a login request that waits shows its card and its form', (
    tester,
  ) async {
    final llm = planningServer()
      ..browsers['budget'] = ChatBrowser(
        tab: _tab('waiting'),
        logins: [
          BrowserLogin(
            card: Uri.parse(
              'https://h:8445/_live/browser/login/lr-${'a' * 32}.png',
            ),
            page: Uri.parse(
              'https://h:8445/_live/browser/login/lr-${'a' * 32}',
            ),
            state: 'waiting',
            site: 'github.com',
          ),
        ],
      )
      ..frames['budget'] = pixel;
    final h = await pumpApp(tester, llm: llm);
    h.shell.showBrowser();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('The agent is asking you for a login.'), findsOneWidget);
    await tester.tap(control('Open the login form'));
    await tester.pump();
    expect(h.opened.single.path, endsWith('lr-${'a' * 32}'));
  });

  testWidgets('the panel follows the browser while it is open', (tester) async {
    final llm = _server('idle');
    final h = await pumpApp(
      tester,
      llm: llm,
      browserEvery: const Duration(milliseconds: 200),
    );
    h.shell.showBrowser();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.text('The agent has it but is not using it now.'),
      findsOneWidget,
    );
    llm.browsers['budget'] = ChatBrowser(tab: _tab('working'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('The agent is using it.'), findsOneWidget);
    // The picture is read again each second, an unchanged one without its bytes.
    final reads = llm.browserReads
        .where((c) => c == 'browserFrame:budget')
        .length;
    await tester.pump(const Duration(seconds: 2));
    expect(
      llm.browserReads.where((c) => c == 'browserFrame:budget').length,
      greaterThan(reads),
    );
    h.shell.closeBrowser();
    await tester.pump(const Duration(milliseconds: 500));
    final closed = llm.browserReads
        .where((c) => c == 'browserFrame:budget')
        .length;
    await tester.pump(const Duration(seconds: 3));
    expect(
      llm.browserReads.where((c) => c == 'browserFrame:budget').length,
      closed,
    );
    expect(
      llm.browserReads.where((c) => c == 'chatBrowser:budget').length,
      lessThan(20),
    );
  });

  testWidgets(
    'the card shows from the agent\'s first step, before any answer has one',
    (tester) async {
      final llm = planningServer()..hold = true;
      final h = await pumpApp(tester, llm: llm);
      await typeAndEnter(tester, 'Read HN');
      await tester.pump(const Duration(milliseconds: 100));
      expect(control('Browser'), findsNothing);
      // The agent opens a page: the server now has a tab, and the status line says a step.
      llm.browsers['budget'] = ChatBrowser(tab: _tab('working'));
      llm.frames['budget'] = pixel;
      llm.chat!.add(
        const StatusChunk('Opening news.ycombinator.com', tool: 'browse'),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(control('Browser, in use now'), findsOneWidget);
      await tester.tap(control('Browser, in use now'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Hacker News'), findsOneWidget);
      llm.chat!
        ..add(const WholeAnswer('Read it.'))
        ..add(const ChatDone([]));
      await llm.chat!.close();
      await tester.pump(const Duration(milliseconds: 100));
      await _close(tester, h);
    },
  );

  testWidgets('a browser the server says is closed offers no take over', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: _server('closed'));
    h.shell.showBrowser();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('The browser is closed.'), findsOneWidget);
    expect(control('Take over'), findsNothing);
  });
}
