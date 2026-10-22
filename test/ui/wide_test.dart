import 'package:anywherellm/ui/chat/chat_view.dart';
import 'package:anywherellm/ui/settings/settings_dialog.dart';
import 'package:anywherellm/ui/shelf.dart';
import 'package:anywherellm/ui/sidebar.dart';

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

const desktop = Size(1440, 900);

Finder inSidebar(Finder finder) =>
    find.descendant(of: find.byType(Sidebar), matching: finder);

Finder inChat(Finder finder) =>
    find.descendant(of: find.byType(ChatView), matching: finder);

void main() {
  testWidgets('a wide window has the chats as a sidebar, not a shelf', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer(), size: desktop);
    await tester.pumpAndSettle();

    expect(find.byType(Sidebar), findsOneWidget);
    expect(inSidebar(find.text('Quarter priorities')), findsOneWidget);
    expect(inSidebar(find.text('Documents')), findsOneWidget);
    expect(inSidebar(find.text('Settings')), findsOneWidget);
    // The header leaves Chats and New chat to the sidebar.
    expect(inChat(control('Chats')), findsNothing);
    expect(inChat(control('New chat')), findsNothing);
  });

  testWidgets('a narrower window keeps the shelf', (tester) async {
    await pumpApp(tester, llm: planningServer(), size: const Size(1100, 800));
    await tester.pumpAndSettle();

    expect(find.byType(Sidebar), findsNothing);
    expect(inChat(control('Chats')), findsOneWidget);
  });

  testWidgets('a chat picked in the sidebar opens and is marked chosen', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer(), size: desktop);
    await tester.pumpAndSettle();

    await tester.tap(inSidebar(find.text('Budget questions')));
    await tester.pumpAndSettle();

    expect(inChat(find.text('About 40k.')), findsOneWidget);
    final row = tester.getSemantics(
      inSidebar(control('Budget questions')).first,
    );
    expect(row.flagsCollection.isSelected, Tristate.isTrue);
  });

  testWidgets('Settings opens beside the sidebar', (tester) async {
    await pumpApp(tester, llm: planningServer(), size: desktop);
    await tester.pumpAndSettle();

    await tester.tap(inSidebar(find.text('Settings')));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsDialog), findsOneWidget);
    expect(find.byType(Sidebar), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(SettingsDialog)).dx,
      greaterThanOrEqualTo(256),
    );

    // A chat picked in the sidebar closes Settings.
    await tester.tap(inSidebar(find.text('Quarter priorities')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
  });

  testWidgets('a shelf left open closes when the sidebar takes its place', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      llm: planningServer(),
      size: const Size(1100, 800),
    );
    await tester.pumpAndSettle();
    h.shell.openShelf();
    await tester.pumpAndSettle();
    expect(find.byType(ChatsShelf), findsOneWidget);

    tester.view.physicalSize = desktop;
    await tester.pumpAndSettle();
    expect(h.shell.shelfOpen, isFalse);

    // Narrower again, the shelf does not come back.
    tester.view.physicalSize = const Size(1100, 800);
    await tester.pumpAndSettle();
    expect(find.byType(ChatsShelf), findsNothing);
  });

  testWidgets(
    'the chat keeps its draft as the window crosses the sidebar\'s width',
    (tester) async {
      await pumpApp(tester, llm: planningServer(), size: const Size(1100, 800));
      await tester.pumpAndSettle();
      await tester.enterText(composerField, 'half a thought');

      tester.view.physicalSize = desktop;
      await tester.pumpAndSettle();
      expect(find.byType(Sidebar), findsOneWidget);
      expect(find.text('half a thought'), findsOneWidget);
    },
  );
}
