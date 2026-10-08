import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/chat/browser_panel.dart';
import 'package:anywherellm/ui/chat/card_image.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pixels.dart';
import '../support/pump.dart';

Finder control(String label) => find.byWidgetPredicate(
  (widget) => widget is Tappable && widget.label == label,
);

final _card = Uri.parse('https://h:8445/_live/browser/bw-3aeecef2b460eeb7.jpg');
final _page = Uri.parse('https://h:8445/_live/browser/bw-3aeecef2b460eeb7');

/// A card line as the browser's skills give it.
String _cardLine([String title = 'Browser: Hacker News']) =>
    'Card: [![$title]($_card)]($_page)';

/// Pumps a fixed time: while the browser is in use its dot pulses, so nothing settles.
Future<void> _wait(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 400));

void main() {
  testWidgets('a running answer names its browser step and shows the browser', (
    tester,
  ) async {
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    await typeAndEnter(tester, 'Read HN');
    llm.chat!.add(
      const StatusChunk('Opening news.ycombinator.com', tool: 'browse'),
    );
    await _wait(tester);
    expect(find.text('Browser · Opening news.ycombinator.com'), findsOneWidget);
    expect(control('Browser, in use now'), findsOneWidget);

    await tester.tap(find.text('Browser · Opening news.ycombinator.com'));
    await _wait(tester);
    expect(h.shell.browserOpen, isTrue);
    expect(
      find.text('The agent is using it: Opening news.ycombinator.com'),
      findsOneWidget,
    );
    expect(find.text('1. Opening news.ycombinator.com'), findsOneWidget);

    // Another tool's status is a status line again.
    llm.chat!.add(const StatusChunk('Running web-browsing'));
    await _wait(tester);
    expect(find.text('Running web-browsing'), findsOneWidget);
    expect(control('Browser'), findsOneWidget);

    llm.chat!
      ..add(const WholeAnswer('Read it.'))
      ..add(const ChatDone([]));
    await llm.chat!.close();
    await tester.pumpAndSettle();
    // No card came, so the answer keeps what the browser did.
    await tester.tap(find.text('Used the browser · 1 step'));
    await tester.pumpAndSettle();
    expect(find.text('1. Opening news.ycombinator.com'), findsNWidgets(2));

    // The chat used the browser, so Browser stays, and its panel, still open, says no card
    // came.
    expect(control('Browser'), findsOneWidget);
    expect(h.shell.browserOpen, isTrue);
    expect(
      find.text('The agent has not shown this chat\'s browser yet.'),
      findsOneWidget,
    );
    expect(find.text('The last answer\'s steps'), findsOneWidget);
  });

  testWidgets(
    'a login request\'s card stands for the browser, and opens its form',
    (tester) async {
      final form = Uri.parse(
        'https://h:8445/_live/browser/login/lr-${'b' * 32}',
      );
      final llm = planningServer()..hold = true;
      final h = await pumpApp(tester, llm: llm);
      await typeAndEnter(tester, 'Log me in');
      llm.chat!
        ..add(
          const StatusChunk('Asking you for a login', tool: 'browser-login'),
        )
        ..add(WholeAnswer('Card: [![Log in to example.com]($form.png)]($form)'))
        ..add(const ChatDone([]));
      await llm.chat!.close();
      await tester.pumpAndSettle();
      expect(find.textContaining('Used the browser'), findsNothing);

      await tester.tap(control('Browser'));
      await tester.pumpAndSettle();
      expect(find.text('The agent is asking you for a login.'), findsOneWidget);
      await tester.tap(control('Open the login form'));
      await tester.pumpAndSettle();
      expect(h.opened, [form]);
    },
  );

  testWidgets('Refresh reads the chat again from the server', (tester) async {
    final llm = planningServer();
    await pumpApp(tester, llm: llm);
    llm.histories['budget'] = [
      ...llm.histories['budget']!,
      const ChatMessage(role: Role.user, text: 'Asked on the phone'),
      const ChatMessage(role: Role.assistant, text: 'Answered on the phone.'),
    ];
    await tester.tap(control('Read this chat again from the server'));
    await tester.pumpAndSettle();
    expect(find.text('Answered on the phone.'), findsOneWidget);
  });

  testWidgets('a chat with a card has Browser in its header, with Take over', (
    tester,
  ) async {
    final llm = answering('Done.\n\n${_cardLine()}')..images[_card] = [pixel];
    final h = await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    expect(find.textContaining('Used the browser'), findsNothing);

    await tester.tap(control('Browser'));
    await tester.pumpAndSettle();
    expect(h.shell.browserOpen, isTrue);
    expect(
      find.descendant(
        of: find.byType(BrowserPanel),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    await tester.tap(control('Take over'));
    await tester.pumpAndSettle();
    expect(h.opened, [_page]);

    // Esc takes the browser out and puts Sources back as it was.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.shell.browserOpen, isFalse);
    expect(h.shell.sourcesOpen, isTrue);
  });

  testWidgets('a closed browser panel lets go of the live card', (
    tester,
  ) async {
    final llm = answering(_cardLine())..images[_card] = [pixel];
    final h = await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    h.shell.showBrowser();
    await tester.pumpAndSettle();
    Finder inPanel() => find.descendant(
      of: find.byType(BrowserPanel),
      matching: find.byType(CardImage),
    );
    expect(TickerMode.valuesOf(tester.element(inPanel())).enabled, isTrue);

    // Files hides the panel but keeps it built, and its card stops following.
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    expect(h.shell.sourcesOpen, isFalse);
    expect(TickerMode.valuesOf(tester.element(inPanel())).enabled, isFalse);
  });

  testWidgets('a login card still opens its form', (tester) async {
    final form = Uri.parse('https://h:8445/_live/browser/login/lr-${'a' * 32}');
    final h = await pumpApp(
      tester,
      llm: answering('Card: [![Log in to example.com]($form.png)]($form)'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('[Log in to example.com: did not load]'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(h.opened, [form]);
    expect(h.shell.browserOpen, isFalse);
  });
}
