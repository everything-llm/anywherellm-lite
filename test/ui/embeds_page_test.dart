import 'package:anywherellm/core/embeds.dart';
import 'package:anywherellm/ui/settings/embeds_page.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/widgets/controls.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// A control on the embeds page, by the label a screen reader hears.
Finder control(String label) => find.descendant(
  of: find.byType(EmbedsPage),
  matching: find.byWidgetPredicate(
    (widget) => widget is Tappable && widget.label == label,
  ),
);

Future<Harness> openEmbeds(
  WidgetTester tester,
  FakeAnythingLlm llm, {
  Size size = const Size(740, 1000),
}) async {
  final h = await pumpApp(tester, llm: llm, size: size);
  h.shell.openSettings(SettingsPage.embeds);
  await tester.pumpAndSettle();
  return h;
}

Future<void> pickWorkspace(WidgetTester tester, String name) async {
  await tapVisible(
    tester,
    find
        .descendant(
          of: find.byType(EmbedsPage),
          matching: find.byType(DropdownButton<String>),
        )
        .last,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

const _embed = Embed(
  uuid: 'e-1',
  workspace: 'Q3 planning',
  mode: EmbedMode.query,
  enabled: true,
  chats: 3,
);

void main() {
  testWidgets(
    'a wide screen shows an embed as a row of columns, and its HTML',
    (tester) async {
      final llm = planningServer()..embedList = [_embed];
      await openEmbeds(tester, llm);
      for (final column in ['WORKSPACE', 'MODE', 'CHATS', 'ON']) {
        expect(find.text(column), findsOneWidget);
      }
      Finder onPage(String text) => find.descendant(
        of: find.byType(EmbedsPage),
        matching: find.text(text),
      );
      final row = tester.getCenter(onPage('3')).dy;
      expect(tester.getCenter(onPage('Q3 planning').first).dy, row);
      expect(find.textContaining('data-embed-id="e-1"'), findsNothing);
      await tapVisible(tester, control('HTML'));
      await tester.pumpAndSettle();
      expect(find.textContaining('data-embed-id="e-1"'), findsOneWidget);
    },
  );

  testWidgets('a narrow screen stacks an embed, with no columns', (
    tester,
  ) async {
    final llm = planningServer()..embedList = [_embed];
    await openEmbeds(tester, llm, size: const Size(360, 640));
    expect(find.text('WORKSPACE'), findsNothing);
    expect(find.text('3 chats'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new embed answers in Chat, from the workspace picked', (
    tester,
  ) async {
    final llm = planningServer();
    await openEmbeds(tester, llm);
    expect(find.text('No embeds yet.'), findsOneWidget);
    final y = tester.getTopLeft;
    expect(
      y(find.text('No embeds yet.')).dy,
      lessThan(y(find.text('New embed')).dy),
    );
    await pickWorkspace(tester, 'Household');
    await tapVisible(tester, control('Create embed'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('createEmbed:household'));
    expect(llm.embedList.single.mode, EmbedMode.chat);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('a limit of 0 is refused, and empty means none', (tester) async {
    final llm = planningServer();
    await openEmbeds(tester, llm);
    await tester.enterText(find.bySemanticsLabel('Chats per day').last, '0');
    await tapVisible(tester, control('Create embed'));
    await tester.pumpAndSettle();
    expect(llm.calls, isNot(contains(startsWith('createEmbed'))));
    expect(
      find.text('A limit is a whole number above 0, or empty for no limit.'),
      findsOneWidget,
    );
  });

  testWidgets('a workspace made after the page opens can be picked', (
    tester,
  ) async {
    final h = await openEmbeds(tester, planningServer());
    await h.chat.createWorkspace('Travel');
    await tester.pump();
    await pickWorkspace(tester, 'Travel');
    await tapVisible(tester, control('Create embed'));
    await tester.pumpAndSettle();
    expect(h.llm.calls, contains('createEmbed:travel'));
  });

  testWidgets('an embed turns off, and is deleted after asking', (
    tester,
  ) async {
    final llm = planningServer()..embedList = [_embed];
    await openEmbeds(tester, llm);
    await tapVisible(
      tester,
      find.descendant(
        of: find.byType(EmbedsPage),
        matching: find.byType(AppSwitch),
      ),
    );
    await tester.pumpAndSettle();
    expect(llm.embedList.single.enabled, isFalse);
    await tapVisible(tester, control('Delete'));
    await tester.pumpAndSettle();
    expect(llm.calls, isNot(contains('deleteEmbed:e-1')));
    expect(
      find.textContaining('Delete the embed for Q3 planning?'),
      findsOneWidget,
    );
    await tapVisible(tester, control('Delete').last);
    await tester.pumpAndSettle();
    expect(llm.calls, contains('deleteEmbed:e-1'));
    expect(find.text('No embeds yet.'), findsOneWidget);
  });

  testWidgets('an embed\'s chats show on asking', (tester) async {
    final llm = planningServer()
      ..embedList = [_embed]
      ..embedChatsOf['e-1'] = [
        const EmbedChat(
          session: 's',
          question: 'Opening hours?',
          answer: '9 to 5.',
        ),
      ];
    await openEmbeds(tester, llm);
    await tapVisible(tester, control('Chats'));
    await tester.pumpAndSettle();
    expect(find.text('Opening hours?'), findsOneWidget);
    expect(find.text('9 to 5.'), findsOneWidget);
  });

  testWidgets('the page fits a phone, with a long workspace name', (
    tester,
  ) async {
    final llm = planningServer()
      ..embedList = [
        const Embed(
          uuid: 'e-1',
          workspace: 'A workspace with a very long name that will not fit',
          mode: EmbedMode.query,
          enabled: true,
        ),
      ];
    await openEmbeds(tester, llm, size: const Size(360, 640));
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(EmbedsPage), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
