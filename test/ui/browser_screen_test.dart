import 'package:anywherellm/core/browser.dart';
import 'package:anywherellm/ui/chat/browser_item.dart';
import 'package:anywherellm/ui/chat/card_image.dart';
import 'package:anywherellm/ui/widgets/sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pixels.dart';
import '../support/pump.dart';

const _phone = Size(390, 844);
const _view = 'https://h:8454/tok/?tab=bw-3aeecef2b460eeb7';
final _card = Uri.parse('https://h:8445/_live/browser/bw-3aeecef2b460eeb7.jpg');
final _page = Uri.parse('https://h:8445/_live/browser/bw-3aeecef2b460eeb7');

BrowserTab _tab(String state) => BrowserTab(
  page: Uri.parse(_view),
  state: state,
  title: 'Boiler service',
  site: 'example-heating.se',
  last: 'Typed the postcode',
);

/// Pumps a fixed time: while the browser is in use its dot pulses, so nothing settles.
Future<void> _wait(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 400));

int _sent(FakeAnythingLlm llm, String message) =>
    llm.calls.where((c) => c.endsWith(':$message')).length;

void main() {
  testWidgets(
    'on a phone with a web view the browser is the take-over view, full screen',
    (tester) async {
      final llm = planningServer()
        ..browsers['budget'] = ChatBrowser(tab: _tab('waiting'));
      final h = await pumpApp(
        tester,
        llm: llm,
        size: _phone,
        canTakeOver: true,
      );
      await _wait(tester);
      await tester.tap(control('Browser'));
      await _wait(tester);
      // In the app's theme, which the view keeps to whatever the device's.
      expect(find.text('Take-over view of $_view&theme=light'), findsOneWidget);
      expect(find.byType(SheetFrame), findsNothing);
      expect(tester.takeException(), isNull);
      // The page's Back returns to the chat, and so does the system's.
      await tester.tap(control('Page back'));
      await _wait(tester);
      expect(h.shell.browserOpen, isFalse);
      h.shell.showBrowser();
      await _wait(tester);
      await tester.binding.handlePopRoute();
      await _wait(tester);
      expect(h.shell.browserOpen, isFalse);
    },
  );

  testWidgets('without a web view a phone keeps the browser\'s sheet', (
    tester,
  ) async {
    final llm = planningServer()
      ..browsers['budget'] = ChatBrowser(tab: _tab('idle'))
      ..frames['budget'] = pixel;
    final h = await pumpApp(tester, llm: llm, size: _phone);
    await _wait(tester);
    h.shell.showBrowser();
    await _wait(tester);
    expect(find.byType(SheetFrame), findsOneWidget);
    h.shell.closeBrowser();
    await _wait(tester);
  });

  testWidgets('a message from the browser\'s bar is sent into the chat', (
    tester,
  ) async {
    final llm = planningServer()
      ..browsers['budget'] = ChatBrowser(tab: _tab('user'));
    final h = await pumpApp(tester, llm: llm, size: _phone, canTakeOver: true);
    h.shell.showBrowser();
    await _wait(tester);
    final line = await h.takeover.say('Pick the Tuesday slot');
    await _wait(tester);
    expect(line, 'Sent: Pick the Tuesday slot');
    expect(_sent(llm, 'Pick the Tuesday slot'), 1);
  });

  testWidgets(
    'while the chat answers, a message from the browser goes when the answer ends',
    (tester) async {
      final llm = planningServer()
        ..hold = true
        ..browsers['budget'] = ChatBrowser(tab: _tab('idle'));
      final h = await pumpApp(
        tester,
        llm: llm,
        size: _phone,
        canTakeOver: true,
      );
      await tester.enterText(composerField, 'Book the boiler service');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _wait(tester);
      h.shell.showBrowser();
      await _wait(tester);
      final line = await h.takeover.say('Use my work email');
      await _wait(tester);
      expect(line, 'Sends when this answer ends: Use my work email');
      expect(_sent(llm, 'Use my work email'), 0);
      h.shell.closeBrowser();
      await _wait(tester);
      expect(find.text('Sends when this answer ends.'), findsOneWidget);
      await llm.chat!.close();
      await _wait(tester);
      expect(_sent(llm, 'Use my work email'), 1);
      await llm.chat!.close();
      await _wait(tester);
    },
  );

  testWidgets('a phone draws a browser card as the app\'s item', (
    tester,
  ) async {
    final llm =
        answering(
            'I have the booking page open.\n\n'
            'Card: [![Browser: Boiler service]($_card)]($_page)',
          )
          ..browsers['budget'] = ChatBrowser(tab: _tab('user'))
          ..images[_card] = [pixel];
    final h = await pumpApp(tester, llm: llm, size: _phone, canTakeOver: true);
    await _wait(tester);
    expect(find.byType(BrowserItem), findsOneWidget);
    expect(find.byType(CardImage), findsNothing);
    expect(find.text('Boiler service'), findsOneWidget);
    expect(find.text('You have the tab · example-heating.se'), findsOneWidget);
    await tester.tap(find.text('Open browser'));
    await _wait(tester);
    expect(h.shell.browserOpen, isTrue);
    expect(find.text('Take-over view of $_view&theme=light'), findsOneWidget);
  });

  testWidgets('a desktop keeps the card\'s picture', (tester) async {
    final llm = answering(
      'Done.\n\nCard: [![Browser: Boiler service]($_card)]($_page)',
    )..images[_card] = [pixel];
    await pumpApp(tester, llm: llm);
    await _wait(tester);
    expect(find.byType(BrowserItem), findsNothing);
    expect(find.byType(CardImage), findsOneWidget);
  });

  test('the item says who has the tab and whose page it is', () {
    expect(
      browserItemLine(_tab('user')),
      'You have the tab · example-heating.se',
    );
    expect(
      browserItemLine(BrowserTab(page: Uri.parse(_view), state: 'waiting')),
      'Waiting for you',
    );
  });
}
