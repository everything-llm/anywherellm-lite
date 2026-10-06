import 'package:anywherellm/core/embeds.dart';
import 'package:anywherellm/ui/files/embeds_view.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/widgets/controls.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// A control on the embeds page, by the label a screen reader hears.
Finder control(String label) => find.descendant(
  of: find.byType(EmbedsView),
  matching: find.byWidgetPredicate(
    (widget) => widget is Tappable && widget.label == label,
  ),
);

Future<Harness> openEmbeds(
  WidgetTester tester,
  FakeAnythingLlm llm, {
  Size size = const Size(1400, 1000),
}) async {
  final h = await pumpApp(tester, llm: llm, size: size);
  h.shell.showPane(Pane.files);
  await tester.pumpAndSettle();
  h.files.select('/settings/embeds');
  await tester.pumpAndSettle();
  return h;
}

void main() {
  testWidgets('an embed shows its workspace, chats and HTML', (tester) async {
    final llm = planningServer()
      ..embedList = [
        const Embed(
          uuid: 'e-1',
          workspace: 'Q3 planning',
          mode: EmbedMode.chat,
          enabled: true,
          chats: 3,
        ),
      ];
    await openEmbeds(tester, llm);
    expect(find.text('3 chats · e-1'), findsOneWidget);
    expect(find.textContaining('data-embed-id="e-1"'), findsOneWidget);
  });

  testWidgets('a new embed is made for the workspace picked', (tester) async {
    final llm = planningServer();
    await openEmbeds(tester, llm);
    expect(find.text('No embeds yet.'), findsOneWidget);
    await tester.tap(control('Household'));
    await tester.pump();
    await tester.tap(control('Make embed'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('createEmbed:household'));
    expect(find.text('0 chats · embed-1'), findsOneWidget);
  });

  testWidgets('an embed turns off, and is deleted after asking', (
    tester,
  ) async {
    final llm = planningServer()
      ..embedList = [
        const Embed(
          uuid: 'e-1',
          workspace: 'Q3 planning',
          mode: EmbedMode.query,
          enabled: true,
        ),
      ];
    await openEmbeds(tester, llm);
    await tester.tap(
      find.descendant(
        of: find.byType(EmbedsView),
        matching: find.byType(AppSwitch),
      ),
    );
    await tester.pumpAndSettle();
    expect(llm.embedList.single.enabled, isFalse);
    await tester.tap(control('Delete'));
    await tester.pumpAndSettle();
    expect(llm.calls, isNot(contains('deleteEmbed:e-1')));
    expect(
      find.textContaining('Delete the embed for Q3 planning?'),
      findsOneWidget,
    );
    await tester.tap(control('Delete'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('deleteEmbed:e-1'));
    expect(find.text('No embeds yet.'), findsOneWidget);
  });

  testWidgets('an embed\'s chats show on asking', (tester) async {
    final llm = planningServer()
      ..embedList = [
        const Embed(
          uuid: 'e-1',
          workspace: 'Q3 planning',
          mode: EmbedMode.query,
          enabled: true,
          chats: 1,
        ),
      ]
      ..embedChatsOf['e-1'] = [
        const EmbedChat(
          session: 's',
          question: 'Opening hours?',
          answer: '9 to 5.',
        ),
      ];
    await openEmbeds(tester, llm);
    await tester.tap(control('Show chats'));
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
    await tester.drag(find.byType(EmbedsView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
