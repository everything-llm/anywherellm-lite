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
      isA<SharedPairing>(),
      reason: 'a link it cannot use is offered as a pairing, which says why',
    );
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

  testWidgets('a link the server refuses says why and leaves nothing of it in '
      'the form', (tester) async {
    final shares = StreamController<SharedItem>();
    final h = await pumpApp(tester, connection: null, shares: shares);
    h.llm.verifyError = const ApiException('The server refused this API key.');
    await _open(tester, shares, _link());
    await tester.tap(_inSheet(control('Connect')));
    await tester.pumpAndSettle();
    expect(h.shell.settingsPage, SettingsPage.connection);
    expect(h.settings.connection, isNull);
    expect(find.text('The server refused this API key.'), findsOneWidget);
    expect(holding('K9'), findsNothing);
    expect(
      holding('https://ai.example.com'),
      findsNothing,
      reason: 'a key typed next must not go to the address the link named',
    );
    await shares.close();
  });

  testWidgets('over a saved server, a refused link gives back the saved '
      'address', (tester) async {
    final shares = StreamController<SharedItem>();
    final h = await pumpApp(tester, shares: shares);
    final saved = h.settings.connection;
    h.llm.verifyError = const ApiException('The server refused this API key.');
    await _open(tester, shares, _link());
    await tester.tap(_inSheet(control('Connect')));
    await tester.pumpAndSettle();
    expect(h.settings.connection, saved);
    expect(find.text('The server refused this API key.'), findsOneWidget);
    expect(holding('K9'), findsNothing);
    await tester.tap(control('Edit connection'));
    await tester.pumpAndSettle();
    expect(holding('K9'), findsNothing);
    expect(holding('https://ai.example.com'), findsNothing);
    expect(holding(saved!.baseUrl), findsOneWidget);
    await shares.close();
  });

  testWidgets('it warns of each address over plain http', (tester) async {
    final shares = StreamController<SharedItem>();
    await pumpApp(tester, shares: shares);
    await _open(
      tester,
      shares,
      Uri(
        scheme: 'anywherellm',
        host: 'connect',
        queryParameters: {
          'url': 'http://nas:3001',
          'key': 'K9',
          'toolkit': 'http://bridge.lan:8467',
        },
      ).toString(),
    );
    expect(_inSheet(find.text('Plain http')), findsNWidgets(2));
    expect(
      _inSheet(find.textContaining('whatever answers nas ')),
      findsOneWidget,
    );
    expect(
      _inSheet(find.textContaining('whatever answers bridge.lan ')),
      findsOneWidget,
    );
    await shares.close();
  });

  testWidgets('it shows a long address whole', (tester) async {
    final shares = StreamController<SharedItem>();
    await pumpApp(tester, shares: shares);
    const address =
        'https://home.tail1234.ts.net.and-a-long-name-that-hides-the-end.evil.example';
    await _open(
      tester,
      shares,
      Uri(
        scheme: 'anywherellm',
        host: 'connect',
        queryParameters: {'url': address, 'key': 'K9'},
      ).toString(),
    );
    final shown = tester.widget<Text>(_inSheet(find.text(address)));
    expect(shown.maxLines, isNull);
    expect(tester.takeException(), isNull);
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

  testWidgets('a pairing link pasted as the address asks first, then '
      'connects with the toolkit\'s address', (tester) async {
    final h = await pumpApp(tester, connection: null);
    await _paste(
      tester,
      h,
      'Server address',
      _link(toolkit: 'https://toolkit.example.com'),
      press: 'Connect',
    );
    expect(h.llm.verified, isEmpty, reason: 'nothing is sent before Connect');
    await tester.tap(_inSheet(control('Connect')));
    await tester.pumpAndSettle();
    expect(h.settings.connection?.baseUrl, 'https://ai.example.com');
    expect(
      h.settings.addressOf(toolkitCompanion),
      Uri.parse('https://toolkit.example.com'),
    );
    expect(
      holding(_link(toolkit: 'https://toolkit.example.com')),
      findsNothing,
    );
  });

  testWidgets('a pairing link pasted in Edit connection replaces the saved '
      'server once Connect is pressed', (tester) async {
    final h = await pumpApp(tester);
    await _paste(
      tester,
      h,
      'AnythingLLM server address',
      _link(),
      press: 'Save key',
      edit: true,
    );
    expect(h.settings.connection, sampleConnection);
    await tester.tap(_inSheet(control('Connect')));
    await tester.pumpAndSettle();
    expect(h.settings.connection?.baseUrl, 'https://ai.example.com');
  });
}

/// Pastes [link] in [h]'s Connection page's address field named [field], in Edit connection
/// when [edit], and presses [press], which offers it in Connect to this server?.
Future<void> _paste(
  WidgetTester tester,
  Harness h,
  String field,
  String link, {
  required String press,
  bool edit = false,
}) async {
  h.shell.openSettings(SettingsPage.connection);
  await tester.pumpAndSettle();
  if (edit) {
    await tapVisible(tester, control('Edit connection'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.bySemanticsLabel(field).last, link);
  await tapVisible(tester, control(press));
  await tester.pumpAndSettle();
  expect(_inSheet(find.text('Connect to this server?')), findsOneWidget);
}
