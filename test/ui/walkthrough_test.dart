import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/settings/walkthrough.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_toolkit.dart';
import '../support/pump.dart';

/// Opens the first run's Connection page with nothing saved, as the app does at such a start.
Future<Harness> _firstRun(WidgetTester tester, {bool canScan = false}) async {
  final h = await pumpApp(tester, connection: null, canScan: canScan);
  h.shell.openSettings(SettingsPage.connection);
  await tester.pumpAndSettle();
  return h;
}

/// Taps How connecting works where it can be tapped, which is the camera's while it shows.
Future<void> _openGuide(WidgetTester tester) async {
  final link = control('How connecting works');
  await tester.ensureVisible(link.last);
  await tester.pumpAndSettle();
  await tester.tap(link.hitTestable().first);
  await tester.pumpAndSettle();
}

/// Opens the list of Settings on a server whose toolkit is [present] or not.
Future<Harness> _settings(
  WidgetTester tester, {
  bool present = false,
  bool canScan = false,
}) async {
  final h = await pumpApp(
    tester,
    toolkitServer: FakeToolkit(present: present),
    canScan: canScan,
  );
  h.shell.openSettings();
  await tester.pumpAndSettle();
  return h;
}

void main() {
  group('How connecting works', () {
    testWidgets('the first run opens the guide, which steps and closes', (
      tester,
    ) async {
      final h = await _firstRun(tester);
      expect(
        find.text('https, or http on your home network or Tailscale.'),
        findsOneWidget,
      );
      await _openGuide(tester);
      expect(h.shell.guide, Guide.connect);
      expect(find.byType(Walkthrough), findsOneWidget);
      expect(find.text('1 of ${connectSteps.length}'), findsOneWidget);
      expect(find.text('Phone and server'), findsOneWidget);
      expect(control('Previous screen'), findsNothing);
      await tester.tap(find.text('Begin'));
      await tester.pumpAndSettle();
      expect(find.text('2 of ${connectSteps.length}'), findsOneWidget);
      expect(find.text('THE KEY'), findsOneWidget);
      await tester.tap(control('Screen 3: The address'));
      await tester.pumpAndSettle();
      expect(find.text('3 of ${connectSteps.length}'), findsOneWidget);
      expect(find.textContaining('box.tail1234.ts.net'), findsOneWidget);
      await tester.tap(control('Previous screen'));
      await tester.pumpAndSettle();
      expect(find.text('2 of ${connectSteps.length}'), findsOneWidget);
      await tester.tap(control('Close'));
      await tester.pumpAndSettle();
      expect(h.shell.guiding, isFalse);
      expect(find.byType(Walkthrough), findsNothing);
      expect(h.shell.settingsOpen, isTrue);
    });

    testWidgets('a swipe and the arrow keys move between screens', (
      tester,
    ) async {
      await _firstRun(tester);
      await _openGuide(tester);
      await tester.fling(find.byType(Walkthrough), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('2 of ${connectSteps.length}'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('3 of ${connectSteps.length}'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('2 of ${connectSteps.length}'), findsOneWidget);
    });

    testWidgets('the last screen scans a code where there is a camera', (
      tester,
    ) async {
      final h = await _firstRun(tester, canScan: true);
      await _openGuide(tester);
      await tester.tap(control('Screen ${connectSteps.length}: The address'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan QR code').last);
      await tester.pumpAndSettle();
      expect(h.shell.guiding, isFalse);
      expect(h.shell.scanning, isTrue);
      expect(find.text('Fake scan'), findsOneWidget);
    });

    testWidgets('without a camera the last screen closes the guide', (
      tester,
    ) async {
      final h = await _firstRun(tester);
      await _openGuide(tester);
      await tester.tap(control('Screen ${connectSteps.length}: The address'));
      await tester.pumpAndSettle();
      await tester.tap(control('Close, then type the address and key'));
      await tester.pumpAndSettle();
      expect(h.shell.guiding, isFalse);
      expect(h.shell.scanning, isFalse);
    });

    testWidgets(
      'opened from the camera, it lies over it and Back closes it first',
      (tester) async {
        final h = await _firstRun(tester, canScan: true);
        await tester.tap(control('Scan QR code'));
        await tester.pumpAndSettle();
        await _openGuide(tester);
        expect(h.shell.guiding, isTrue);
        expect(find.text('Fake scan').hitTestable(), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(h.shell.guiding, isFalse);
        expect(h.shell.scanning, isTrue);
        expect(find.text('Fake scan').hitTestable(), findsOneWidget);
      },
    );
  });

  group('Add the toolkit', () {
    testWidgets('Settings offers it while no toolkit answers, and opens it', (
      tester,
    ) async {
      final h = await _settings(tester);
      expect(find.text('Get more from your server'), findsOneWidget);
      await tapVisible(tester, control('See how to add it'));
      await tester.pumpAndSettle();
      expect(h.shell.guide, Guide.toolkit);
      expect(find.text('Add the toolkit'), findsOneWidget);
      expect(find.text('1 of ${toolkitSteps.length}'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.textContaining('anythingllm-toolkit gui'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.shell.guiding, isFalse);
      expect(h.shell.settingsOpen, isTrue);
    });

    testWidgets('a server with the toolkit is not offered it', (tester) async {
      await _settings(tester, present: true);
      expect(find.text('Get more from your server'), findsNothing);
      expect(find.text('Memory'), findsOneWidget);
    });

    testWidgets('the installer\'s page says which AnythingLLM is picked', (
      tester,
    ) async {
      final h = await _settings(tester);
      h.shell.showGuide(Guide.toolkit);
      await tester.pumpAndSettle();
      await tester.tap(control('Screen 3: Step 2 · Add it'));
      await tester.pumpAndSettle();
      expect(find.textContaining('AnythingLLM Desktop: its'), findsOneWidget);
      await tester.tap(control('anythingllm, a podman container'));
      await tester.pumpAndSettle();
      expect(find.textContaining('anythingllm: a podman'), findsOneWidget);
    });

    testWidgets('its end opens Connection with the camera reading', (
      tester,
    ) async {
      final h = await _settings(tester, canScan: true);
      h.shell.showGuide(Guide.toolkit);
      await tester.pumpAndSettle();
      await tester.tap(control('Screen ${toolkitSteps.length}: Step 3 · Scan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan the installer\'s code'));
      await tester.pumpAndSettle();
      expect(h.shell.guiding, isFalse);
      expect(h.shell.settingsPage, SettingsPage.connection);
      expect(h.shell.scanning, isTrue);
      expect(find.text('Fake scan'), findsOneWidget);
    });

    testWidgets('without a camera its end closes it', (tester) async {
      final h = await _settings(tester);
      h.shell.showGuide(Guide.toolkit);
      await tester.pumpAndSettle();
      await tester.tap(control('Screen ${toolkitSteps.length}: Step 3 · Scan'));
      await tester.pumpAndSettle();
      await tester.tap(control('Close, scan it on a phone with a camera'));
      await tester.pumpAndSettle();
      expect(h.shell.guiding, isFalse);
      expect(h.shell.scanning, isFalse);
      expect(h.shell.settingsPage, isNull);
    });
  });
}
