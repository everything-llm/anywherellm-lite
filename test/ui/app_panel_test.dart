import 'dart:async';

import 'package:anywherellm/ui/chat/app_panel.dart';
import 'package:anywherellm/ui/chat/card_image.dart';
import 'package:anywherellm/ui/chat/message_list.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pixels.dart';
import '../support/pump.dart';

final _card = Uri.parse('https://h:8455/_live/apps/q3/groceries.png');
final _page = Uri.parse('https://h:8447/q3/apps/groceries/');

/// The chat's last answer holds the Groceries app's card, linked to its page.
FakeAnythingLlm _withApp() =>
    answering('Added oat milk.\n\n[![Groceries]($_card)]($_page)\n')
      ..images[_card] = [pixel];

/// Taps the app's card in the chat. A one-pixel picture is drawn square, taller than the chat
/// shows: its top is tapped.
Future<void> _tapCard(WidgetTester tester) async {
  await tester.tapAt(
    tester.getTopLeft(
          find
              .descendant(
                of: find.byType(MessageList),
                matching: find.byType(Image),
              )
              .first,
        ) +
        const Offset(20, 20),
  );
  await tester.pumpAndSettle();
}

/// Whether the card in the chat is ringed in the accent.
bool _ringed(WidgetTester tester) {
  final ring = tester.widget<DecoratedBox>(
    find
        .ancestor(
          of: find
              .byWidgetPredicate((w) => w is CardImage && w.uri == _card)
              .first,
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (ring.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false;
}

void main() {
  testWidgets(
    'on a desktop the card opens its app beside the chat, ringed while it shows',
    (tester) async {
      final h = await pumpApp(tester, llm: _withApp());
      expect(find.text('Live · click to open beside the chat'), findsOneWidget);
      expect(_ringed(tester), isFalse);
      await _tapCard(tester);
      expect(h.shell.appOpen, isTrue);
      expect(h.shell.beside, Beside.app);
      expect(h.opened, isEmpty);
      final panel = find.byType(AppPanel);
      expect(
        find.descendant(of: panel, matching: find.text('Groceries')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('App · Q3 planning')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.byWidgetPredicate(
            (w) => w is CardImage && w.uri == _card,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Live · open beside the chat'), findsOneWidget);
      expect(_ringed(tester), isTrue);
      await tester.tap(control('Open in the browser'));
      await tester.pump();
      expect(h.opened, [_page]);
      await tester.tap(find.descendant(of: panel, matching: control('Close')));
      await tester.pumpAndSettle();
      expect(h.shell.appOpen, isFalse);
      expect(h.shell.sourcesOpen, isTrue);
      expect(_ringed(tester), isFalse);
    },
  );

  testWidgets('Esc and Back put back what the panel showed', (tester) async {
    final h = await pumpApp(tester, llm: _withApp(), sourcesOpen: false);
    await _tapCard(tester);
    expect(h.shell.appOpen, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.shell.appOpen, isFalse);
    expect(h.shell.rightOpen, isFalse);
    h.shell.showBrowser();
    await tester.pumpAndSettle();
    await _tapCard(tester);
    expect(h.shell.appOpen, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.shell.browserOpen, isTrue);
  });

  testWidgets('the browser over an app puts the app back, then Sources', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: _withApp());
    await _tapCard(tester);
    h.shell.showBrowser();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.shell.appOpen, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.shell.sourcesOpen, isTrue);
  });

  testWidgets('the app\'s live card is followed only while its panel is open', (
    tester,
  ) async {
    final live = StreamController<Uint8List>.broadcast();
    addTearDown(live.close);
    final llm = answering('Added oat milk.\n\n[![Groceries]($_card)]($_page)\n')
      ..liveImages[_card] = live;
    final h = await pumpApp(tester, llm: llm);
    live.add(Uint8List.fromList(pixel));
    await tester.pumpAndSettle();
    await _tapCard(tester);
    expect(find.byType(AppPanel), findsOneWidget);
    expect(live.hasListener, isTrue);
    h.shell.closeApp();
    await tester.pumpAndSettle();
    h.chat.newChat();
    await tester.pumpAndSettle();
    // Neither the chat nor the closed panel shows the card any more.
    expect(live.hasListener, isFalse);
  });

  group('on a phone', () {
    const phone = Size(390, 844);

    testWidgets('the card opens its app in a sheet over the chat', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: _withApp(), size: phone);
      expect(find.text('Live · tap to open'), findsOneWidget);
      await _tapCard(tester);
      final sheet = find.byType(AppSheet);
      expect(sheet, findsOneWidget);
      expect(find.byType(AppPanel), findsNothing);
      expect(
        find.descendant(of: sheet, matching: find.text('Groceries')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('App · Q3 planning')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.descendant(of: sheet, matching: control('Open in the browser')),
      );
      await tester.pump();
      expect(h.opened, [_page]);
      // A tap on the scrim above the sheet closes it.
      await tester.tapAt(const Offset(195, 30));
      await tester.pumpAndSettle();
      expect(find.byType(AppSheet), findsNothing);
      expect(h.shell.appOpen, isFalse);
    });

    testWidgets('Back and a drag down close the sheet', (tester) async {
      final h = await pumpApp(tester, llm: _withApp(), size: phone);
      await _tapCard(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AppSheet), findsNothing);
      await _tapCard(tester);
      expect(find.byType(AppSheet), findsOneWidget);
      await tester.drag(
        find.descendant(
          of: find.byType(AppSheet),
          matching: find.text('Groceries'),
        ),
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppSheet), findsNothing);
      expect(h.shell.rightOpen, isFalse);
    });
  });
}
