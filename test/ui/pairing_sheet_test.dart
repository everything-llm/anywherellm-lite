import 'dart:async';

import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:anywherellm/ui/settings/pairing_sheet.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/share/share_sheet.dart';
import 'package:anywherellm/ui/share/shared_item.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// A pairing link to `https://ai.example.com` with the key `K9`, naming the toolkit's address
/// when [toolkit] is set.
String _link({String? toolkit}) => Uri(
  scheme: 'anywherellm',
  host: 'connect',
  queryParameters: {
    'url': 'https://ai.example.com',
    'key': 'K9',
    'toolkit': ?toolkit,
  },
).toString();

/// Opens [link] in the app, as Android hands over a tapped `anywherellm://` link.
Future<void> _open(
  WidgetTester tester,
  StreamController<SharedItem> shares,
  String link,
) async {
  shares.add(sharedTextItem(link));
  await tester.pumpAndSettle();
}

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(PairingSheet), matching: finder);

void main() {
  test('a pairing link alone is a pairing, not a link to add', () {
    expect(sharedTextItem(' ${_link()} '), isA<SharedPairing>());
    expect(
      sharedTextItem('https://example.test/a'),
      isA<SharedLink>(),
      reason: 'a web page is still offered to add or ask about',
    );
    expect(sharedTextItem('Pair with ${_link()}'), isA<SharedText>());
    expect(
      sharedTextItem('anywherellm://signed-in?service=github'),
      isA<SharedSignIn>().having((s) => s.service, 'service', 'github'),
    );
    expect(
      sharedTextItem('anywherellm://signed-in?service=%3Cb%3E'),
      isA<SharedPairing>(),
      reason: 'a link it cannot use is offered as a pairing, which says why',
    );
  });

  testWidgets('a signed-in link brings the chat back with the message in its '
      'composer, and sends nothing', (tester) async {
    final shares = StreamController<SharedItem>();
    final h = await pumpApp(tester, shares: shares);
    h.shell.openSettings();
    await tester.pumpAndSettle();
    await _open(tester, shares, 'anywherellm://signed-in?service=github');
    expect(h.shell.settingsOpen, isFalse);
    expect(find.byType(PairingSheet), findsNothing);
    expect(find.byType(ShareSheet), findsNothing);
    expect(composerText(tester), 'I\'ve signed in to github.');
    expect(h.llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
    await shares.close();
  });

  testWidgets('a link connects once Connect is pressed, with the toolkit\'s '
      'address', (tester) async {
    final shares = StreamController<SharedItem>();
    final h = await pumpApp(tester, connection: null, shares: shares);
    await _open(tester, shares, _link(toolkit: 'https://toolkit.example.com'));
    expect(_inSheet(find.text('Connect to this server?')), findsOneWidget);
    expect(_inSheet(find.text('https://ai.example.com')), findsOneWidget);
    expect(_inSheet(find.text('https://toolkit.example.com')), findsOneWidget);
    expect(find.byType(ShareSheet), findsNothing);
    expect(h.llm.verified, isEmpty, reason: 'nothing is sent before Connect');
    await tester.tap(_inSheet(control('Connect')));
    await tester.pumpAndSettle();
    expect(find.byType(PairingSheet), findsNothing);
    expect(h.shell.settingsPage, SettingsPage.connection);
    expect(h.settings.connection?.baseUrl, 'https://ai.example.com');
    expect(h.settings.connection?.apiKey, 'K9');
    expect(
      h.settings.addressOf(toolkitCompanion),
      Uri.parse('https://toolkit.example.com'),
    );
    await shares.close();
  });

  testWidgets('a key the server refuses shows in its field, under why', (
    tester,
  ) async {
    final shares = StreamController<SharedItem>();
    final h = await pumpApp(tester, connection: null, shares: shares);
    h.llm.verifyError = const ApiException('The server refused this API key.');
    await _open(tester, shares, _link());
    await tester.tap(_inSheet(control('Connect')));
    await tester.pumpAndSettle();
    expect(h.shell.settingsPage, SettingsPage.connection);
    expect(h.settings.connection, isNull);
    expect(find.text('The server refused this API key.'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is EditableText && w.controller.text == 'K9',
      ),
      findsOneWidget,
    );
    await shares.close();
  });

  testWidgets('a refused key shows in its field over a saved server too', (
    tester,
  ) async {
    final shares = StreamController<SharedItem>();
    final h = await pumpApp(tester, shares: shares);
    final saved = h.settings.connection;
    h.llm.verifyError = const ApiException('The server refused this API key.');
    await _open(tester, shares, _link());
    await tester.tap(_inSheet(control('Connect')));
    await tester.pumpAndSettle();
    expect(h.settings.connection, saved);
    expect(find.text('The server refused this API key.'), findsOneWidget);
    Finder holding(String text) => find.byWidgetPredicate(
      (w) => w is EditableText && w.controller.text == text,
    );
    expect(holding('K9'), findsOneWidget);
    await tester.tap(control('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(control('Edit connection'));
    await tester.pumpAndSettle();
    expect(holding('K9'), findsNothing, reason: 'the refused key is let go');
    expect(holding(saved!.baseUrl), findsOneWidget);
    await shares.close();
  });

  testWidgets('it names the server it replaces, and Cancel keeps that one', (
    tester,
  ) async {
    final shares = StreamController<SharedItem>();
    final h = await pumpApp(tester, shares: shares);
    await _open(tester, shares, _link());
    expect(
      _inSheet(find.textContaining('It replaces ${sampleConnection.host}.')),
      findsOneWidget,
    );
    await tester.tap(_inSheet(control('Cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(PairingSheet), findsNothing);
    expect(h.settings.connection, sampleConnection);
    await shares.close();
  });

  testWidgets('Back closes it without connecting', (tester) async {
    final shares = StreamController<SharedItem>();
    final h = await pumpApp(tester, shares: shares);
    await _open(tester, shares, _link());
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PairingSheet), findsNothing);
    expect(h.settings.connection, sampleConnection);
    await shares.close();
  });

  testWidgets('a link it cannot use says why', (tester) async {
    final shares = StreamController<SharedItem>();
    final h = await pumpApp(tester, shares: shares);
    await _open(tester, shares, 'anywherellm://connect?url=https%3A%2F%2Fai');
    expect(
      _inSheet(find.text('This is not an AnywhereLLM pairing code.')),
      findsOneWidget,
    );
    await tester.tap(_inSheet(control('Close')));
    await tester.pumpAndSettle();
    expect(find.byType(PairingSheet), findsNothing);
    expect(h.settings.connection, sampleConnection);
    await shares.close();
  });
}
