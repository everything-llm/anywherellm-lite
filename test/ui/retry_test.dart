import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('Ask again says why it is off for a question sent with files', (
    tester,
  ) async {
    await pumpApp(tester, llm: askedWithFiles(['photo.png']));
    await tester.tap(control('More: read aloud, ask again, details'));
    await tester.pumpAndSettle();
    final row = control(
      'Ask again is off: the files sent with the question are not kept',
    );
    expect(row, findsOneWidget);
    expect(tester.widget<Tappable>(row).onTap, isNull);
  });
}
