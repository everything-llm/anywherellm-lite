import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Retry says why it is off for a question sent with files', (
    tester,
  ) async {
    await pumpApp(tester, llm: askedWithFiles(['photo.png']));
    expect(
      find.byTooltip(
        'Retry is off: the files sent with the question are not kept',
      ),
      findsOneWidget,
    );
  });
}
