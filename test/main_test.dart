import 'dart:ui' show Size;

import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/main.dart';
import 'package:anywherellm/ui/app.dart';
import 'package:anywherellm/ui/settings/settings_dialog.dart';
import 'package:anywherellm/ui/state/prefs_controller.dart';
import 'package:anywherellm/ui/state/settings_controller.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';
import 'support/fake_settings.dart';

Future<void> _boot(
  WidgetTester tester,
  FakeSettingsStore store, [
  FakePrefsStore? prefsStore,
]) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final llm = planningServer();
  await tester.pumpWidget(
    AnywhereLlmApp(
      home: SessionHost(
        llm: llm,
        settings: SettingsController(llm, store, ConnectionHolder()),
        prefs: PrefsController(prefsStore ?? FakePrefsStore()),
        shell: ShellController(),
        launch: (_) async => true,
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

  testWidgets('with a last chat saved, the app opens on it', (tester) async {
    final prefsStore = FakePrefsStore(
      const Prefs(lastChat: LastChat('q3', 'priorities')),
    );
    await _boot(tester, FakeSettingsStore(sampleConnection), prefsStore);
    // Opening any other chat would have saved it in place of this one.
    expect(prefsStore.saved.lastChat, const LastChat('q3', 'priorities'));
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
