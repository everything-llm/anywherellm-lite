import 'package:anywherellm/ui/apps/json_view.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_apps.dart';
import '../support/pump.dart';

/// Settings' list, with [apps] beside the server.
Future<Harness> _settings(WidgetTester tester, FakeApps apps) async {
  final h = await pumpApp(
    tester,
    llm: planningServer(),
    appsServer: apps,
    onChat: false,
  );
  await tester.pumpAndSettle();
  await tester.tap(control('Settings'));
  await tester.pumpAndSettle();
  return h;
}

/// Taps the entry named [name] in the folder shown.
Future<void> _open(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('System files walks the tree, read only, and Back steps up', (
    tester,
  ) async {
    final h = await _settings(tester, groceriesServer());
    await tester.tap(find.text('System files'));
    await tester.pumpAndSettle();
    expect(h.shell.settingsPage, SettingsPage.systemFiles);
    expect(find.text('4 entries'), findsOneWidget);
    for (final folder in ['apps/', 'runner/', 'settings/', 'skill/']) {
      expect(find.text(folder), findsOneWidget);
    }
    expect(find.textContaining('Secrets are named'), findsOneWidget);

    await _open(tester, 'skill/');
    expect(find.text('skill/'), findsOneWidget); // the meta line
    expect(find.text('lib/'), findsOneWidget);
    await _open(tester, 'handler.js');
    expect(find.text('module.exports.runtime = {}'), findsOneWidget);
    expect(h.appsServer.calls, contains('systemFile:skill/handler.js'));

    // Back goes to the folder, then the top, then Settings' list.
    await tester.tap(control('Back to skill'));
    await tester.pumpAndSettle();
    expect(find.text('lib/'), findsOneWidget);
    await tester.tap(control('Back to System files'));
    await tester.pumpAndSettle();
    expect(find.text('runner/'), findsOneWidget);
    await tester.tap(control('Back to Settings'));
    await tester.pumpAndSettle();
    expect(h.shell.settingsPage, isNull);
  });

  testWidgets(
    'a JSON file reads as JSON or raw, and a binary file is named only',
    (tester) async {
      final h = await _settings(tester, groceriesServer());
      h.shell.showSettingsPage(SettingsPage.systemFiles);
      h.shell.showSystemPath('apps/home/groceries/app.json', folder: false);
      await tester.pumpAndSettle();
      expect(find.byType(JsonView), findsOneWidget);
      await tester.tap(control('Show the raw file'));
      await tester.pumpAndSettle();
      expect(find.byType(JsonView), findsNothing);
      expect(find.byType(NumberedText), findsOneWidget);

      h.shell.showSystemPath(
        'runner/anythingllm_apps_v2/assets/fonts/Sans.ttf',
        folder: false,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('not text'), findsOneWidget);
    },
  );

  testWidgets('a read that fails says why', (tester) async {
    final h = await _settings(tester, groceriesServer());
    h.shell.showSettingsPage(SettingsPage.systemFiles);
    h.shell.showSystemPath('nope.txt', folder: false);
    await tester.pumpAndSettle();
    expect(find.text('Could not read this'), findsOneWidget);
    expect(find.text("No file 'nope.txt'."), findsOneWidget);
  });

  testWidgets('an older apps server shows no System files', (tester) async {
    final apps = groceriesServer()..older = true;
    final h = await _settings(tester, apps);
    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('System files'), findsNothing);
    expect(h.apps.systemFiles, isFalse);
  });

  testWidgets('beside a stock AnythingLLM there is no System files row', (
    tester,
  ) async {
    final h = await _settings(tester, FakeApps());
    expect(find.text('System files'), findsNothing);
    expect(h.apps.systemFiles, isFalse);
  });
}
