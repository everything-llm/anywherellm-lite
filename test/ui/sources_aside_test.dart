import 'dart:ui';

import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/chat/message_list.dart';
import 'package:anywherellm/ui/chat/sources_aside.dart';
import 'package:flutter/widgets.dart' show Scrollable;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

Finder inAside(Finder finder) =>
    find.descendant(of: find.byType(SourcesAside), matching: finder);

/// The planning server with two answers in Budget questions, each citing its own sources.
FakeAnythingLlm citingServer() {
  final llm = planningServer();
  llm.histories['budget'] = [
    const ChatMessage(role: Role.user, text: 'Who did we interview?'),
    const ChatMessage(
      role: Role.assistant,
      text: 'Twelve customers.',
      citations: [
        Citation(
          'Customer interviews.docx',
          passages: [Passage('We spoke to twelve customers.', score: 0.71)],
        ),
      ],
    ),
    const ChatMessage(role: Role.user, text: 'What is the budget?'),
    ChatMessage(
      role: Role.assistant,
      text: 'About 40k.',
      citations: [
        const Citation(
          'Q3 roadmap.pdf',
          passages: [Passage('The budget for Q3 is 40k.', score: 0.82)],
        ),
        Citation('Example prices', url: Uri.https('example.com', '/prices')),
      ],
    ),
  ];
  return llm;
}

Future<Harness> openBudget(WidgetTester tester, Size size) async {
  final h = await pumpApp(tester, llm: citingServer(), size: size);
  await tester.pumpAndSettle();
  await h.chat.open('budget');
  await tester.pumpAndSettle();
  return h;
}

void main() {
  testWidgets('beside the chat, the latest answer\'s sources show', (
    tester,
  ) async {
    await openBudget(tester, const Size(1440, 900));

    expect(find.byType(SourcesAside), findsOneWidget);
    expect(inAside(find.text('2 sources')), findsOneWidget);
    expect(inAside(find.text('Q3 roadmap.pdf')), findsOneWidget);
    expect(inAside(find.text('82% match')), findsOneWidget);
    expect(inAside(find.text('The budget for Q3 is 40k.')), findsOneWidget);
    expect(inAside(find.text('example.com')), findsOneWidget);
    expect(inAside(find.text('Customer interviews.docx')), findsNothing);
  });

  testWidgets('a chip picks its source in the panel, opening nothing', (
    tester,
  ) async {
    final h = await openBudget(tester, const Size(960, 600));

    await tester.tap(control('Source 1: Customer interviews.docx'));
    await tester.pumpAndSettle();

    expect(h.shell.popup.value, isNull);
    expect(inAside(find.text('Customer interviews.docx')), findsOneWidget);
    expect(inAside(find.text('71% match')), findsOneWidget);
    expect(inAside(find.text('Q3 roadmap.pdf')), findsNothing);
    final row = tester.getSemantics(
      inAside(control('Source 1: Customer interviews.docx, 71% match')),
    );
    expect(row.flagsCollection.isSelected, Tristate.isTrue);
    expect(inAside(find.text('Open in Documents')), findsOneWidget);

    // A row picks its source too.
    await tester.tap(control('Source 1: Customer interviews.docx'));
    await tester.pumpAndSettle();
    expect(h.shell.aside.value?.source, 0);
  });

  testWidgets('a web page picked in the panel opens as a page', (tester) async {
    final h = await openBudget(tester, const Size(1440, 900));

    await tester.tap(inAside(control('Source 2: example.com')));
    await tester.pumpAndSettle();

    expect(h.shell.aside.value?.source, 1);
    expect(inAside(find.text('Open page')), findsOneWidget);
  });

  testWidgets('a phone keeps the passages sheet and no panel', (tester) async {
    final h = await openBudget(tester, phoneSize);

    expect(find.byType(SourcesAside), findsNothing);
    await tester.tap(control('Source 1: Customer interviews.docx'));
    await tester.pumpAndSettle();
    expect(h.shell.popup.value, isA<Citation>());
  });

  testWidgets('a short wide window has no panel', (tester) async {
    await openBudget(tester, const Size(1440, 470));

    expect(find.byType(SourcesAside), findsNothing);
  });

  testWidgets('a chat with no sources says where they will show', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      llm: planningServer(),
      size: const Size(1440, 900),
    );
    await tester.pumpAndSettle();
    await h.chat.open('priorities');
    await tester.pumpAndSettle();

    expect(
      inAside(find.text('The sources an answer draws on show here.')),
      findsOneWidget,
    );
  });

  for (final (size, scale) in [
    (const Size(1440, 900), 1.0),
    (const Size(960, 600), 1.0),
    (const Size(960, 600), 2.0),
  ]) {
    testWidgets('the panel fits at ${size.width.round()}x'
        '${size.height.round()}, text ${scale}x', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openBudget(tester, size);
      // At large text the earlier answer may lie above the chat's fold, not yet built.
      final source = control('Source 1: Customer interviews.docx');
      await tester.scrollUntilVisible(
        source,
        100,
        scrollable: find
            .descendant(
              of: find.byType(MessageList),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(source);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
