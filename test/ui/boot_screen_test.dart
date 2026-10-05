import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything/ui/app.dart';
import 'package:everything/ui/boot_screen.dart';

void main() {
  testWidgets('a boot error says why and offers another try', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      NilsApp(
        home: BootError(message: 'nope', onRetry: () => retried = true),
      ),
    );
    expect(find.text('The libraries could not be read'), findsOneWidget);
    expect(find.text('nope'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('a boot error scrolls on a screen too short for it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      NilsApp(
        home: BootError(message: 'nope ' * 40, onRetry: () {}),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Try again'), 50);
    expect(find.text('Try again'), findsOneWidget);
  });
}
