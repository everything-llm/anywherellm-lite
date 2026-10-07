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
}
