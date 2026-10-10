import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('on a phone, a tap beside a small control still reaches it', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      llm: planningServer(),
      size: const Size(390, 844),
      sourcesOpen: false,
    );
    // Documents is drawn 36 px tall; its target is 44.
    final documents = tester.getCenter(find.byTooltip('Documents'));
    await tester.tapAt(documents + const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.shell.sourcesOpen, isTrue);
  });

  /// The composer's card: the box with a shadow around the message field.
  BoxDecoration card(WidgetTester tester) => tester
      .widgetList<Container>(
        find.ancestor(of: composerField, matching: find.byType(Container)),
      )
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .firstWhere((d) => d.boxShadow != null);

  testWidgets(
    'on a phone, the composer has a fainter edge and rounder corners',
    (tester) async {
      await pumpApp(
        tester,
        llm: planningServer(),
        size: const Size(390, 844),
        sourcesOpen: false,
      );
      final t = Tokens.of(tester.element(composerField));
      final phone = card(tester);
      expect((phone.border! as Border).top.color, t.line2);
      expect(phone.borderRadius, BorderRadius.circular(20));
    },
  );

  testWidgets('on a desktop, the composer keeps its edge and corners', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer());
    final t = Tokens.of(tester.element(composerField));
    final desktop = card(tester);
    expect((desktop.border! as Border).top.color, t.line);
    expect(desktop.borderRadius, BorderRadius.circular(16));
  });
}
