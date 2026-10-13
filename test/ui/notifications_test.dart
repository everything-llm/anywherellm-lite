import 'package:anywherellm/core/apps.dart';
import 'package:anywherellm/core/push.dart';
import 'package:anywherellm/ui/settings/rows.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_apps.dart';
import '../support/fake_pusher.dart';
import '../support/pump.dart';

/// The app on the Notifications page, with an apps server beside the server unless
/// [appsServer] says otherwise.
Future<Harness> _onPage(
  WidgetTester tester, {
  FakePusher? pusher,
  FakeApps? appsServer,
  FakeAnythingLlm? llm,
}) async {
  final harness = await pumpApp(
    tester,
    llm: llm,
    pusher: pusher ?? FakePusher(),
    appsServer: appsServer ?? FakeApps(present: true),
    onChat: false,
  );
  harness.shell.openSettings(SettingsPage.notifications);
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  testWidgets(
    'Settings has no Notifications where the device takes no pushes',
    (tester) async {
      final harness = await pumpApp(tester, onChat: false);
      harness.shell.openSettings();
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsNothing);
    },
  );

  testWidgets('Settings opens Notifications', (tester) async {
    final harness = await pumpApp(tester, pusher: FakePusher(), onChat: false);
    harness.shell.openSettings();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
    expect(harness.shell.settingsPage, SettingsPage.notifications);
  });

  testWidgets(
    'turning on subscribes this device to the apps server, with its key',
    (tester) async {
      final pusher = FakePusher();
      final harness = await _onPage(tester, pusher: pusher);
      expect(harness.push!.on, isFalse);

      await tester.tap(control('Notifications'));
      await tester.pumpAndSettle();

      expect(pusher.using, 'io.heckel.ntfy');
      expect(pusher.calls, ['register:apps:BAppsKey']);
      expect(harness.appsServer.pushDevices.values, [
        FakePusher.endpointOf(PushSource.apps),
      ]);
      expect(find.widgetWithText(InfoRow, 'Scheduled jobs'), findsNothing);
      expect(find.widgetWithText(InfoRow, 'Apps'), findsOneWidget);
      expect(find.text('On'), findsOneWidget);
    },
  );

  testWidgets('a source its server cannot send from says why', (tester) async {
    final harness = await _onPage(tester, appsServer: FakeApps());
    await tester.tap(control('Notifications'));
    await tester.pumpAndSettle();

    expect(find.text('Not available'), findsOneWidget);
    expect(
      find.text('Apps: No apps server runs beside this server.'),
      findsOneWidget,
    );
    expect(harness.appsServer.pushDevices, isEmpty);
  });

  testWidgets('an older apps server is told apart from none', (tester) async {
    await _onPage(tester, appsServer: FakeApps(present: true, older: true));
    await tester.tap(control('Notifications'));
    await tester.pumpAndSettle();
    expect(
      find.text('Apps: This apps server cannot send notifications. Update it.'),
      findsOneWidget,
    );
  });

  testWidgets('with no distributor installed it says to install one', (
    tester,
  ) async {
    final pusher = FakePusher(installed: const [], byDefault: null);
    final harness = await _onPage(tester, pusher: pusher);
    await tester.tap(control('Notifications'));
    await tester.pumpAndSettle();
    expect(harness.push!.on, isFalse);
    expect(
      find.text(
        'Install a UnifiedPush distributor, such as ntfy, then turn notifications on.',
      ),
      findsOneWidget,
    );
    expect(pusher.calls, isEmpty);
  });

  testWidgets('a refused permission leaves them off', (tester) async {
    final pusher = FakePusher()..allowed = false;
    final harness = await _onPage(tester, pusher: pusher);
    await tester.tap(control('Notifications'));
    await tester.pumpAndSettle();
    expect(harness.push!.on, isFalse);
    expect(find.textContaining('Allow them in its settings'), findsOneWidget);
  });

  testWidgets('with several distributors and no default it asks which', (
    tester,
  ) async {
    final pusher = FakePusher(
      installed: const ['io.heckel.ntfy', 'org.unifiedpush.distributor.sunup'],
      byDefault: null,
    );
    final harness = await _onPage(tester, pusher: pusher);
    await tester.tap(control('Notifications'));
    await tester.pumpAndSettle();
    expect(harness.push!.on, isFalse);

    await tester.tap(find.text('Sunup'));
    await tester.pumpAndSettle();
    expect(pusher.using, 'org.unifiedpush.distributor.sunup');
    expect(harness.push!.on, isTrue);
    expect(find.text('On'), findsOneWidget);
  });

  testWidgets('a distributor that refuses says why', (tester) async {
    final pusher = FakePusher()
      ..refuse =
          'Open the distributor app: it needs you to finish setting it up.';
    await _onPage(tester, pusher: pusher);
    await tester.tap(control('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Failed'), findsOneWidget);
    expect(
      find.text(
        'Apps: Open the distributor app: it needs you to finish setting it up.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'turning off lets go of the distributor and the apps server forgets',
    (tester) async {
      final pusher = FakePusher();
      final harness = await _onPage(tester, pusher: pusher);
      await tester.tap(control('Notifications'));
      await tester.pumpAndSettle();
      pusher.calls.clear();

      await tester.tap(control('Notifications'));
      await tester.pumpAndSettle();
      expect(harness.push!.on, isFalse);
      expect(pusher.calls, ['unregister:apps']);
      expect(harness.appsServer.pushDevices, isEmpty);
      expect(find.text('Sent by'), findsNothing);
    },
  );

  testWidgets('a distributor already in use registers again at start', (
    tester,
  ) async {
    final pusher = FakePusher()..using = 'io.heckel.ntfy';
    final harness = await _onPage(tester, pusher: pusher);
    expect(harness.push!.on, isTrue);
    expect(pusher.calls, ['register:apps:BAppsKey']);
    expect(harness.appsServer.pushDevices, isNotEmpty);
  });

  testWidgets('another server is subscribed afresh', (tester) async {
    final pusher = FakePusher()..using = 'io.heckel.ntfy';
    final harness = await _onPage(tester, pusher: pusher);
    pusher.calls.clear();
    await harness.settings.connect('https://other.example:3001', 'K2');
    await tester.pumpAndSettle();
    expect(pusher.calls, contains('register:apps:BAppsKey'));
  });

  testWidgets('a dropped registration asks to turn them off and on', (
    tester,
  ) async {
    final pusher = FakePusher()..using = 'io.heckel.ntfy';
    await _onPage(tester, pusher: pusher);
    pusher.drop(PushSource.apps);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Apps: The distributor stopped sending these. Turn notifications off and on again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a tapped notification opens its app', (tester) async {
    final pusher = FakePusher();
    final harness = await pumpApp(
      tester,
      pusher: pusher,
      appsServer: FakeApps(present: true),
    );
    pusher.tap(const AppTarget(AppRef('planning', 'groceries')));
    await tester.pump();
    expect(harness.shell.app, const AppRef('planning', 'groceries'));
  });
}
