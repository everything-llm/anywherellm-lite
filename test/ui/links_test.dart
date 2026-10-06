import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

Finder control(String label) => find.byWidgetPredicate(
  (widget) => widget is Tappable && widget.label == label,
);

/// Taps the link whose text is [text] in a selectable answer, through its span's recognizer:
/// the answer is editable text, which taps on a text range do not reach.
Future<void> tapLink(WidgetTester tester, String text) async {
  TapGestureRecognizer? found;
  for (final selectable in tester.widgetList<SelectableText>(
    find.byType(SelectableText),
  )) {
    selectable.textSpan?.visitChildren((span) {
      if (span is TextSpan &&
          span.text == text &&
          span.recognizer is TapGestureRecognizer) {
        found = span.recognizer! as TapGestureRecognizer;
        return false;
      }
      return true;
    });
  }
  expect(found, isNotNull, reason: 'no link "$text"');
  found!.onTap!();
  await tester.pumpAndSettle();
}

/// The planning server with [answer] as the last answer in the open chat.
FakeAnythingLlm _answering(String answer, {List<Citation> cited = const []}) {
  final llm = planningServer();
  llm.histories['budget'] = [
    const ChatMessage(role: Role.user, text: 'Where?'),
    ChatMessage(role: Role.assistant, text: answer, citations: cited),
  ];
  return llm;
}

void main() {
  testWidgets('a link in an answer opens in the browser', (tester) async {
    final h = await pumpApp(
      tester,
      llm: _answering('Read [the report](https://example.com/report) today.'),
    );
    await tapLink(tester, 'the report');
    expect(h.opened, [Uri.parse('https://example.com/report')]);
    expect(h.chat.problem, isNull);
  });

  testWidgets('a link the app will not open says so', (tester) async {
    final h = await pumpApp(
      tester,
      llm: _answering('Click [here](javascript:alert(1)) now.'),
    );
    await tapLink(tester, 'here');
    expect(h.opened, isEmpty);
    expect(h.chat.problem?.title, 'Could not open the link');
  });

  testWidgets('a link nothing on the device opens says so', (tester) async {
    final h = await pumpApp(
      tester,
      llm: _answering('Mail [me](mailto:ada@example.com).'),
    );
    h.openSucceeds = false;
    await tapLink(tester, 'me');
    expect(h.opened, [Uri.parse('mailto:ada@example.com')]);
    expect(h.chat.problem?.text, contains('Nothing on this device opened'));
  });

  testWidgets(
    'a web citation opens its page; a file one lights up in Sources',
    (tester) async {
      final h = await pumpApp(
        tester,
        llm: _answering(
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
    await pumpApp(
      tester,
      llm: _answering(
        'Card:\n\n[![Report](https://h:8445/card.png)](https://h:8445/r)\n\n'
        'Elsewhere: ![tracker](https://evil.test/p.png?d=secret)',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('[tracker: evil.test]'), findsOneWidget);
  });
}
