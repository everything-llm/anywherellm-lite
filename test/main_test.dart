import 'dart:ui' show Size;

import 'package:everything/core/connection.dart';
import 'package:everything/core/ports.dart';
import 'package:everything/main.dart';
import 'package:everything/ui/app.dart';
import 'package:everything/ui/state/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';
import 'support/fake_settings.dart';

Future<void> _boot(WidgetTester tester, FakeSettingsStore store) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final llm = FakeAnythingLlm();
  final holder = ConnectionHolder();
  await tester.pumpWidget(
    NilsApp(
      home: SessionHost(
        llm: llm,
        holder: holder,
        settings: SettingsController(llm, store, holder),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with nothing saved, the app opens on Settings', (tester) async {
    await _boot(tester, FakeSettingsStore());
    expect(find.text('Server address'), findsWidgets);
  });

  testWidgets('with a saved connection, the app opens on the workspaces', (
    tester,
  ) async {
    await _boot(tester, FakeSettingsStore(sampleConnection));
    expect(find.text('No workspaces yet'), findsOneWidget);
  });

  testWidgets('a keyring that cannot be read still opens the app on Settings', (
    tester,
  ) async {
    await _boot(
      tester,
      FakeSettingsStore()..loadError = const ApiException('locked'),
    );
    expect(find.text('Could not read the saved connection'), findsOneWidget);
  });
}
