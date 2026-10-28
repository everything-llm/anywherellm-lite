import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/settings/walkthrough.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  group('How connecting works', () {
    testWidgets('the first run opens the guide, which steps and closes', (
      tester,
    ) async {
      final h = await _firstRun(tester);
      await _openGuide(tester);
      expect(h.shell.guide, Guide.connect);
      expect(find.byType(Walkthrough), findsOneWidget);
      expect(find.text('1 of ${connectSteps.length}'), findsOneWidget);
      expect(find.text('Phone and server'), findsOneWidget);
      expect(control('Previous screen'), findsNothing);
      await tester.tap(find.text('Begin'));
      await tester.pumpAndSettle();
      expect(find.text('2 of ${connectSteps.length}'), findsOneWidget);
      expect(find.text('The key'), findsOneWidget);
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

    testWidgets('it steps at once when the device asks for less motion', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _firstRun(tester);
      await _openGuide(tester);
      await tester.tap(find.text('Begin'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('2 of ${connectSteps.length}'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('3 of ${connectSteps.length}'), findsOneWidget);
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
}
