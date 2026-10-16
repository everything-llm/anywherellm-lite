import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/tokens.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Send sits at the composer\'s right edge after the chips', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer());
    final field = tester.getRect(composerField);
    final send = tester.getRect(find.byTooltip('Send'));
    expect((field.right - send.right).abs(), lessThan(16));
  });

  testWidgets('a tap beside a small control still reaches it', (tester) async {
    final h = await pumpApp(tester, llm: planningServer());
    // Attach is drawn 30 px across; its target is 44.
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

  testWidgets('the composer has a faint edge and round corners', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer());
    final t = Tokens.of(tester.element(composerField));
    final phone = card(tester);
    expect((phone.border! as Border).top.color, t.line2);
    expect(phone.borderRadius, BorderRadius.circular(28));
  });
}
