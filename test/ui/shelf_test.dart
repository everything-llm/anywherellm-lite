import 'package:anywherellm/ui/chat/chat_view.dart';
import 'package:anywherellm/ui/home.dart';
import 'package:anywherellm/ui/shelf.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// Opens the Chats shelf from the chat's menu button.
Future<void> _openShelf(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Chats'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'the app opens on the chat, and the chats show only as the shelf',
    (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      await tester.pumpAndSettle();
      expect(find.byType(ChatView), findsOneWidget);
      expect(find.byType(ChatsTab), findsNothing);
      h.shell.openShelf();
      await tester.pumpAndSettle();
      expect(find.byType(ChatsTab), findsOneWidget);
    },
  );

  testWidgets('the menu opens the chats from the left over the chat', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer());
    await tester.pumpAndSettle();
    await _openShelf(tester);
    expect(h.shell.shelfOpen, isTrue);
    expect(find.byType(ChatsShelf), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChatsShelf),
        matching: find.byType(ChatsTab),
      ),
      findsOneWidget,
    );

    // A chat picked there shows in the chat, and the shelf closes.
    await tester.tap(
      find.descendant(
        of: find.byType(ChatsShelf),
        matching: find.text('Budget questions'),
      ),
    );
    await tester.pumpAndSettle();
    expect(h.shell.shelfOpen, isFalse);
    expect(h.chat.activeThread, 'budget');
    expect(find.byType(ChatsShelf), findsNothing);
  });

  testWidgets('opening the shelf puts the keyboard away', (tester) async {
    await pumpApp(tester, llm: planningServer());
    await tester.pumpAndSettle();
    await tester.tap(composerField);
    await tester.pump();
    expect(focused(tester, composerField), isTrue);
    await _openShelf(tester);
    expect(focused(tester, composerField), isFalse);
  });

  testWidgets('Back or a tap on the dimmed chat closes the shelf', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer());
    await tester.pumpAndSettle();
    await _openShelf(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.shell.shelfOpen, isFalse);

    await _openShelf(tester);
    await tester.tapAt(
      tester.getTopRight(find.byType(ChatsShelf)) + const Offset(-8, 200),
    );
    await tester.pumpAndSettle();
    expect(h.shell.shelfOpen, isFalse);
  });

  testWidgets('the shelf fits a short phone on its side', (tester) async {
    await pumpApp(tester, llm: planningServer(), size: const Size(740, 360));
    await tester.pumpAndSettle();
    await _openShelf(tester);
    expect(tester.takeException(), isNull);
  });
}
