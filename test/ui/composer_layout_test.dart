import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets(
    'Send sits at the composer\'s right edge beside the server name',
    (tester) async {
      await pumpApp(tester, llm: planningServer());
      final field = tester.getRect(composerField);
      final send = tester.getRect(find.byTooltip('Send'));
      expect((field.right - send.right).abs(), lessThan(16));
    },
  );

  testWidgets('on a phone, a tap beside a small control still reaches it', (
    tester,
  ) async {
    final llm = planningServer();
    await pumpApp(tester, llm: llm, size: const Size(390, 844));
    final reads = llm.calls.where((c) => c == 'workspaces').length;
    // Refresh is drawn 36 px square; its target is 44.
    final refresh = tester.getCenter(find.byTooltip('Refresh'));
    await tester.tapAt(refresh + const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 300));
    expect(llm.calls.where((c) => c == 'workspaces').length, reads + 1);
  });
}
