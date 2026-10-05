import 'package:everything/core/connection.dart';
import 'package:everything/core/ports.dart';
import 'package:everything/ui/state/nav_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
import '../support/pump.dart';

const _saved = Connection(baseUrl: 'https://h:3001', apiKey: 'K1');

Finder _field(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.label == label &&
      widget.properties.textField == true,
);

Finder _text(String label) =>
    find.descendant(of: _field(label), matching: find.byType(TextField));

void main() {
  testWidgets('is in the sidebar', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    expect(h.nav.route, const SettingsRoute());
    expect(find.text('Server address'), findsWidgets);
  });

  testWidgets('starts empty, with the key hidden', (tester) async {
    await pumpApp(tester, route: const SettingsRoute());
    expect(
      tester.widget<TextField>(_text('Server address')).controller!.text,
      '',
    );
    expect(tester.widget<TextField>(_text('API key')).obscureText, isTrue);
  });

  testWidgets('fills in the saved connection when the keyring answers after '
      'the page opened', (tester) async {
    final h = await pumpApp(tester, route: const SettingsRoute());
    h.store.saved = _saved;
    await h.settings.load();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_text('Server address')).controller!.text,
      'https://h:3001',
    );
    final key = tester.widget<TextField>(_text('API key'));
    expect(key.controller!.text, 'K1');
    expect(key.obscureText, isTrue);
    expect(find.text('Remove saved key'), findsOneWidget);
  });

  testWidgets('the eye button shows and hides the key', (tester) async {
    await pumpApp(tester, route: const SettingsRoute());
    await tester.tap(find.byTooltip('Show API key'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_text('API key')).obscureText, isFalse);
    await tester.tap(find.byTooltip('Hide API key'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_text('API key')).obscureText, isTrue);
  });

  testWidgets('Test connection reports success and saves nothing', (
    tester,
  ) async {
    final h = await pumpApp(tester, route: const SettingsRoute());
    await tester.enterText(_text('Server address'), 'https://h:3001');
    await tester.enterText(_text('API key'), 'K1');
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(h.llm.verified.map((c) => c.baseUrl), ['https://h:3001']);
    expect(find.text('Connected to h.'), findsOneWidget);
    expect(h.store.saved, isNull);
  });

  testWidgets('a rejected key is shown as an alert', (tester) async {
    final llm = FakeAnythingLlm()
      ..verifyError = const ApiException('The server rejected the key.');
    await pumpApp(tester, llm: llm, route: const SettingsRoute());
    await tester.enterText(_text('Server address'), 'https://h:3001');
    await tester.enterText(_text('API key'), 'bad');
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(find.text('Could not use these details'), findsOneWidget);
    expect(find.text('The server rejected the key.'), findsOneWidget);
  });

  testWidgets('an empty address is refused before any request', (tester) async {
    final h = await pumpApp(tester, route: const SettingsRoute());
    await tester.enterText(_text('API key'), 'K1');
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the server address.'), findsOneWidget);
    expect(h.llm.verified, isEmpty);
  });

  testWidgets('Save keeps the connection and offers to remove it', (
    tester,
  ) async {
    final h = await pumpApp(tester, route: const SettingsRoute());
    await tester.enterText(_text('Server address'), 'https://h:3001/');
    await tester.enterText(_text('API key'), 'K1');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(h.store.saved, _saved);
    expect(find.text('Saved.'), findsOneWidget);
    expect(find.text('Remove saved key'), findsOneWidget);
    // The address field shows the cleaned address that was saved.
    expect(
      tester.widget<TextField>(_text('Server address')).controller!.text,
      'https://h:3001',
    );
  });

  testWidgets('a keyring that refuses is shown', (tester) async {
    final store = FakeSettingsStore()
      ..saveError = const ApiException(
        'The system keyring could not be written.',
      );
    await pumpApp(tester, store: store, route: const SettingsRoute());
    await tester.enterText(_text('Server address'), 'https://h:3001');
    await tester.enterText(_text('API key'), 'K1');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save the connection'), findsOneWidget);
    expect(
      find.text('The system keyring could not be written.'),
      findsOneWidget,
    );
  });

  testWidgets('Remove saved key empties the fields and the store', (
    tester,
  ) async {
    final store = FakeSettingsStore(_saved);
    final h = await pumpApp(tester, store: store, route: const SettingsRoute());
    await h.settings.load();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove saved key'));
    await tester.pumpAndSettle();
    expect(store.saved, isNull);
    expect(tester.widget<TextField>(_text('API key')).controller!.text, '');
    expect(find.text('Remove saved key'), findsNothing);
  });
}
