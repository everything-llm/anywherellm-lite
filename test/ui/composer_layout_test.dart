import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
