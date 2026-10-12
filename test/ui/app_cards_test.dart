import 'package:anywherellm/core/apps.dart';
import 'package:anywherellm/ui/apps/app_screen.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_apps.dart';
import '../support/pump.dart';

const _groceries = AppRef('q3', 'groceries');
const _card = 'https://h:8466/cards/q3/groceries.png';
const _page = 'https://h:8465/q3/groceries/';

/// The chat with the apps server beside the server, Groceries in Q3 planning.
Future<Harness> _withApps(
  WidgetTester tester, {
  required FakeAnythingLlm llm,
  bool onChat = true,
  bool older = false,
}) async {
  final h = await pumpApp(
    tester,
    llm: llm,
    appsServer: groceriesServer()..older = older,
    canViewApps: true,
    onChat: onChat,
  );
  await tester.pumpAndSettle();
  return h;
}

/// Taps the card's link, as a tap on a linked image in an answer does. The test's picture
/// never decodes, so it has no size to tap.
Future<void> _tapCard(WidgetTester tester) async {
  tester
      .widget<GestureDetector>(
        find
            .ancestor(
              of: find.byType(Image),
              matching: find.byType(GestureDetector),
            )
            .first,
      )
      .onTap!();
  await tester.pumpAndSettle();
}

void main() {
  group('beside a stock AnythingLLM', () {
    testWidgets('an app card still loads as one picture, and opens its page '
        'in the browser', (tester) async {
      final h = await pumpApp(
        tester,
        llm: answering('Here:\n\n[![Groceries]($_card)]($_page)'),
      );
      await tester.pumpAndSettle();
      expect(h.appsServer.cardAsks, [Uri.parse('$_card?once=1&theme=light')]);
      await _tapCard(tester);
      expect(h.opened, [Uri.parse(_page)]);
      expect(find.byType(AppScreen), findsNothing);
    });
  });

  group('beside the apps server', () {
    testWidgets('an app card in an answer is read once, and opens its app', (
      tester,
    ) async {
      final h = await _withApps(
        tester,
        llm: answering('Here:\n\n[![Groceries]($_card)]($_page)'),
        onChat: true,
      );
      expect(h.appsServer.cardAsks, [Uri.parse('$_card?once=1&theme=light')]);
      expect(find.byType(Image), findsOneWidget);
      await _tapCard(tester);
      expect(h.shell.app, _groceries);
      expect(find.text('Web view of $_page?theme=light'), findsOneWidget);
      expect(h.opened, isEmpty);

      // Back shows the chat again, and its card as the app is now.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.shell.app, isNull);
      expect(h.appsServer.cardAsks, hasLength(2));
    });

    testWidgets('a card is read again when its chat opens again, and when its '
        'app changes', (tester) async {
      final h = await _withApps(
        tester,
        llm: answering('Here:\n\n[![Groceries]($_card)]($_page)'),
        onChat: true,
      );
      expect(h.appsServer.cardAsks, hasLength(1));
      h.shell.closeChat();
      await tester.pumpAndSettle();
      h.shell.openChat();
      await tester.pumpAndSettle();
      expect(h.appsServer.cardAsks, hasLength(2));

      await h.apps.rename(_groceries, 'Food');
      await tester.pumpAndSettle();
      expect(h.appsServer.cardAsks, hasLength(3));
    });

    testWidgets('a card read again keeps its picture while its ETag matches, '
        'and is sent again once its app changes', (tester) async {
      final h = await _withApps(
        tester,
        llm: answering('Here:\n\n[![Groceries]($_card)]($_page)'),
      );
      final light = Uri.parse('$_card?once=1&theme=light');
      expect(h.appsServer.cardsUnchanged, isEmpty);
      h.shell.closeChat();
      await tester.pumpAndSettle();
      h.shell.openChat();
      await tester.pumpAndSettle();
      expect(h.appsServer.cardAsks, [light, light]);
      expect(h.appsServer.cardsUnchanged, [light]);
      expect(find.byType(Image), findsOneWidget);

      await h.apps.rename(_groceries, 'Food');
      await tester.pumpAndSettle();
      expect(h.appsServer.cardAsks, hasLength(3));
      expect(h.appsServer.cardsUnchanged, [light]);
    });

    testWidgets('a list read whose version is unchanged reads no card', (
      tester,
    ) async {
      final h = await _withApps(
        tester,
        llm: answering('Here:\n\n[![Groceries]($_card)]($_page)'),
      );
      await h.apps.read('q3');
      await tester.pumpAndSettle();
      await h.apps.read('q3');
      await tester.pumpAndSettle();
      expect(h.appsServer.cardAsks, hasLength(1));
      await h.appsServer.restore(_groceries, 1);
      await h.apps.read('q3');
      await tester.pumpAndSettle();
      expect(h.appsServer.cardAsks, hasLength(2));
    });

    testWidgets('beside an older apps server a card is read whole each time', (
      tester,
    ) async {
      final h = await _withApps(
        tester,
        llm: answering('Here:\n\n[![Groceries]($_card)]($_page)'),
        older: true,
      );
      h.shell.closeChat();
      await tester.pumpAndSettle();
      h.shell.openChat();
      await tester.pumpAndSettle();
      expect(h.appsServer.cardAsks, hasLength(2));
      expect(h.appsServer.cardsUnchanged, isEmpty);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('a bare card opens its app too', (tester) async {
      final h = await _withApps(
        tester,
        llm: answering('Here:\n\n![Groceries]($_card)'),
        onChat: true,
      );
      // The test's picture never decodes, so it has no size to tap.
      tester.widget<Tappable>(control('Open Groceries').first).onTap!();
      await tester.pumpAndSettle();
      expect(h.shell.app, _groceries);
    });

    testWidgets('another image keeps loading as before', (tester) async {
      final chart = Uri.parse('https://h:3001/pictures/chart.png');
      final h = await _withApps(
        tester,
        llm: answering('Here:\n\n![Chart]($chart)'),
        onChat: true,
      );
      expect(h.appsServer.cardAsks, isEmpty);
      expect(h.llm.calls, contains('answerImage:$chart'));
    });
  });
}
