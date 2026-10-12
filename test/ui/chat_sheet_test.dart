import 'package:anywherellm/ui/widgets/sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

const _phone = Size(390, 844);

/// Opens the sheet of the chat on screen from the header's title.
Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('Q3 planning · 2 docs in use'));
  await tester.pumpAndSettle();
}

Finder get _nameField => find.descendant(
  of: find.byType(SheetFrame),
  matching: find.byType(TextField),
);

void main() {
  testWidgets('the name renames the chat as it is typed', (tester) async {
    final h = await pumpApp(tester, llm: planningServer(), size: _phone);
    final thread = h.chat.activeThread!;
    await _openSheet(tester);
    await tester.enterText(_nameField, 'Launch plan');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(
      h.chat.threadsOf('q3').firstWhere((t) => t.slug == thread).name,
      'Launch plan',
    );
    // An empty name keeps the one it has.
    await tester.enterText(_nameField, '  ');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(
      h.chat.threadsOf('q3').firstWhere((t) => t.slug == thread).name,
      'Launch plan',
    );
  });

  testWidgets('Pin to the top pins the chat', (tester) async {
    final h = await pumpApp(tester, llm: planningServer(), size: _phone);
    final thread = h.chat.activeThread!;
    await _openSheet(tester);
    await tester.tap(control('Pin to the top'));
    await tester.pumpAndSettle();
    expect(h.prefs.pinnedIn('q3'), contains(thread));
  });

  testWidgets('Delete chat asks first, and Keep keeps it', (tester) async {
    final h = await pumpApp(tester, llm: planningServer(), size: _phone);
    final thread = h.chat.activeThread!;
    final name = h.chat.title;
    await _openSheet(tester);
    await tester.tap(control('Delete chat'));
    await tester.pumpAndSettle();
    expect(find.text('Delete $name? Its messages go with it.'), findsOneWidget);
    await tester.tap(control('Keep'));
    await tester.pumpAndSettle();
    expect(find.byType(SheetFrame), findsNothing);
    expect(h.chat.threadsOf('q3').map((t) => t.slug), contains(thread));
    await _openSheet(tester);
    await tester.tap(control('Delete chat'));
    await tester.pumpAndSettle();
    await tester.tap(control('Delete'));
    await tester.pumpAndSettle();
    expect(h.chat.threadsOf('q3').map((t) => t.slug), isNot(contains(thread)));
    expect(h.chat.deletedChat, name);
    await h.chat.undoDelete();
  });

  testWidgets('on a new chat the title opens the workspace', (tester) async {
    final h = await pumpApp(tester, llm: planningServer(), size: _phone);
    h.chat.newChat();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Q3 planning · 2 docs in use'));
    await tester.pumpAndSettle();
    expect(h.shell.chatSheet, isNull);
    expect(h.shell.pane.name, 'files');
  });

  testWidgets(
    "the drawer's rows lead to the workspace, the chats and the app",
    (tester) async {
      final h = await pumpApp(tester, llm: planningServer(), size: _phone);
      h.shell.toggleSide();
      await tester.pumpAndSettle();
      expect(find.text('Chats'), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
      // A chat's More opens its sheet, and closes the drawer.
      await tester.tap(control('Rename, pin or delete Budget questions'));
      await tester.pumpAndSettle();
      expect(h.shell.chatSheet?.thread.slug, 'budget');
      expect(h.shell.sideOpen, isFalse);
      h.shell
        ..closePopup()
        ..toggleSide();
      await tester.pumpAndSettle();
      await tester.tap(control('Workspace settings'));
      await tester.pumpAndSettle();
      expect(h.shell.pane.name, 'files');
      h.shell.toggleSide();
      await tester.pumpAndSettle();
      await tester.tap(control('Settings'));
      await tester.pumpAndSettle();
      expect(h.shell.settingsOpen, isTrue);
    },
  );

  testWidgets('a chat deleted from its sheet can be put back over the chat', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer(), size: _phone);
    final thread = h.chat.activeThread!;
    await _openSheet(tester);
    await tester.tap(control('Delete chat'));
    await tester.pumpAndSettle();
    await tester.tap(control('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Chat deleted'), findsOneWidget);
    await tester.tap(control('Undo'));
    await tester.pumpAndSettle();
    expect(h.chat.threadsOf('q3').map((t) => t.slug), contains(thread));
    expect(find.text('Chat deleted'), findsNothing);
  });
}
