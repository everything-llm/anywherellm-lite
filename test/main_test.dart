import 'dart:ui' show Size;

import 'package:everything/core/ports.dart';
import 'package:everything/core/connection.dart';
import 'package:everything/main.dart';
import 'package:everything/ui/app.dart';
import 'package:everything/ui/settings/settings_dialog.dart';
import 'package:everything/ui/state/prefs_controller.dart';
import 'package:everything/ui/state/settings_controller.dart';
import 'package:everything/ui/state/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';
import 'support/fake_settings.dart';

Future<void> _boot(WidgetTester tester, FakeSettingsStore store) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final llm = planningServer();
  await tester.pumpWidget(
    NilsApp(
      home: SessionHost(
        llm: llm,
        settings: SettingsController(llm, store, ConnectionHolder()),
        prefs: PrefsController(FakePrefsStore()),
        shell: ShellController(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with nothing saved, the app opens with Settings over it', (
    tester,
  ) async {
    await _boot(tester, FakeSettingsStore());
    expect(find.byType(SettingsDialog), findsOneWidget);
    expect(find.text('Missing'), findsOneWidget);
  });

  testWidgets('with a saved connection, the app opens on the first workspace', (
    tester,
  ) async {
    await _boot(tester, FakeSettingsStore(sampleConnection));
    expect(find.byType(SettingsDialog), findsNothing);
    expect(find.text('Budget questions'), findsWidgets);
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
