import 'package:anywherellm/core/asks.dart';
import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_toolkit.dart';
import '../support/pump.dart';

FakeToolkit _toolkit() => FakeToolkit()
  ..served = {ToolkitFeature.asks}
  ..allowed = [const AllowedOrigin('http://muse-vm:8463')];

void main() {
  testWidgets('opening the page reads the list again after a failed read', (
    tester,
  ) async {
    final toolkit = _toolkit()
      ..errors['allowedOrigins'] = const ApiException('The bridge is down.');
    final h = await pumpApp(tester, toolkitServer: toolkit);
    h.shell.openSettings(SettingsPage.allowedAddresses);
    await tester.pumpAndSettle();
    expect(find.text('The bridge is down.'), findsOneWidget);
    expect(find.text('http://muse-vm:8463'), findsNothing);

    toolkit.errors.remove('allowedOrigins');
    h.shell.closeSettings();
    await tester.pumpAndSettle();
    h.shell.openSettings(SettingsPage.allowedAddresses);
    await tester.pumpAndSettle();
    expect(find.text('The bridge is down.'), findsNothing);
    expect(find.text('http://muse-vm:8463'), findsOneWidget);
  });

  testWidgets('a failed removal is told beside why the list is stale', (
    tester,
  ) async {
    final toolkit = _toolkit();
    final h = await pumpApp(tester, toolkitServer: toolkit);
    h.shell.openSettings(SettingsPage.allowedAddresses);
    await tester.pumpAndSettle();
    expect(find.text('http://muse-vm:8463'), findsOneWidget);

    toolkit.errors['allowedOrigins'] = const ApiException('Refused.');
    toolkit.errors['forgetOrigin'] = const ApiException('Not removed.');
    await tester.tap(find.text('http://muse-vm:8463'));
    await tester.pumpAndSettle();
    await tester.tap(control('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Not removed.'), findsOneWidget);
    expect(find.text('Refused.'), findsOneWidget);
  });
}
