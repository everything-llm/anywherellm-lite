import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/tokens.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  /// The composer's card: the box with a shadow around the message field.
  Rect cardRect(WidgetTester tester) => tester.getRect(
    find
        .ancestor(of: composerField, matching: find.byType(Container))
        .evaluate()
        .map((e) => find.byElementPredicate((x) => x == e))
        .firstWhere((f) {
          final box = (f.evaluate().single.widget as Container).decoration;
          return box is BoxDecoration && box.boxShadow != null;
        }),
  );

  testWidgets('an empty composer is one line, with Send at its right edge', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer());
    final card = cardRect(tester);
    final send = tester.getRect(find.byTooltip('Send'));
    expect(card.height, lessThan(60));
    expect(card.right - send.right, lessThan(16));
    expect((send.center.dy - card.center.dy).abs(), lessThan(4));
  });

  testWidgets('the message field grows a line at a time, up to a limit', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer());
    final one = cardRect(tester).height;
    await tester.enterText(composerField, 'one\ntwo\nthree');
    await tester.pump();
    final three = cardRect(tester).height;
    expect(three, greaterThan(one + 40));
    await tester.enterText(composerField, List.filled(20, 'line').join('\n'));
    await tester.pump();
    final many = cardRect(tester).height;
    // The field stops at 156 and scrolls, so the card stays near 156 + the row's padding.
    expect(many, lessThan(one + 156));
    // Send stays at the bottom, beside the last line.
    final card = cardRect(tester);
    final send = tester.getRect(find.byTooltip('Send'));
    expect(card.bottom - send.bottom, lessThan(8));
  });

  testWidgets('a tap beside a small control still reaches it', (tester) async {
    final h = await pumpApp(tester, llm: planningServer());
    // Attach is a 48 px square, so a tap 20 px under its middle is still on it.
    final attach = tester.getCenter(
      find.byTooltip('Add files or shortcuts to this message'),
    );
    await tester.tapAt(attach + const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.shell.popup.value, Popup.attach);
  });

  /// The composer's card: the box with a shadow around the message field.
  BoxDecoration card(WidgetTester tester) => tester
      .widgetList<Container>(
        find.ancestor(of: composerField, matching: find.byType(Container)),
      )
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .firstWhere((d) => d.boxShadow != null);

  testWidgets('the composer has a control\'s edge and round corners', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer());
    final t = Tokens.of(tester.element(composerField));
    final phone = card(tester);
    expect((phone.border! as Border).top.color, t.lineStrong);
    expect(phone.borderRadius, BorderRadius.circular(28));
  });
}
