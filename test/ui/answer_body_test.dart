import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/chat/answer_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

const _answer = '''
## The plan

- First **step**
- Second step

```
print('hi');
```

| Name | Due |
|---|---|
| Rent | 1st |
''';

FakeAnythingLlm _server() {
  final llm = planningServer();
  llm.histories['budget'] = [
    const ChatMessage(role: Role.user, text: 'What is the plan?'),
    const ChatMessage(role: Role.assistant, text: _answer),
  ];
  return llm;
}

/// Records what is put on the clipboard.
List<String> _clipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

void main() {
  testWidgets('an answer is drawn as Markdown', (tester) async {
    await pumpApp(tester, llm: _server());
    expect(find.textContaining('## The plan'), findsNothing);
    expect(find.textContaining('The plan', findRichText: true), findsWidgets);
    expect(find.textContaining('Rent', findRichText: true), findsOneWidget);
    expect(find.text("print('hi');"), findsOneWidget);
  });

  testWidgets('Copy answer puts the Markdown on the clipboard', (tester) async {
    final copied = _clipboard(tester);
    await pumpApp(tester, llm: _server());
    await tester.tap(find.bySemanticsLabel('Copy answer').last);
    await tester.pump();
    expect(copied, [_answer.trim()]);
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('Copy code puts only the code on the clipboard', (tester) async {
    final copied = _clipboard(tester);
    await pumpApp(tester, llm: _server());
    await tester.tap(find.bySemanticsLabel('Copy code'));
    await tester.pump();
    expect(copied, ["print('hi');"]);
    await tester.pump(const Duration(seconds: 2));
  });

  group('math', () {
    testWidgets('TeX in dollars and brackets is drawn as math', (tester) async {
      await pumpApp(
        tester,
        llm: answering(r'''
Inline $x^2$ and \(y\).

$$\frac{a}{b}$$

\[ z = 1 \]'''),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Math), findsNWidgets(4));
    });

    testWidgets('prices stay text', (tester) async {
      await pumpApp(tester, llm: answering(r'It costs $5 and $10 a month.'));
      await tester.pumpAndSettle();
      expect(find.byType(Math), findsNothing);
      expect(
        find.textContaining(
          r'It costs $5 and $10 a month.',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('a dollar sign in code is not math', (tester) async {
      await pumpApp(tester, llm: answering(r'Run `echo $HOME$` now.'));
      await tester.pumpAndSettle();
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('TeX that does not parse shows its source', (tester) async {
      await pumpApp(tester, llm: answering(r'Broken: $\frac{a$ here.'));
      await tester.pumpAndSettle();
      expect(find.text(r'$\frac{a$'), findsOneWidget);
    });
  });

  group('code', () {
    Set<Color?> colours(WidgetTester tester) {
      final rich = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((r) => r.text.toPlainText().contains('def add'));
      final found = <Color?>{};
      rich.text.visitChildren((span) {
        if (span is TextSpan && (span.text?.trim().isNotEmpty ?? false)) {
          found.add(span.style?.color);
        }
        return true;
      });
      return found;
    }

    testWidgets('a block in a named language is coloured, and Copy takes it '
        'plain', (tester) async {
      final copied = _clipboard(tester);
      const code = 'def add(a, b):\n    return a + b  # sum';
      await pumpApp(tester, llm: answering('```python\n$code\n```'));
      await tester.pumpAndSettle();
      expect(colours(tester).length, greaterThan(1));
      await tester.tap(find.bySemanticsLabel('Copy code'));
      await tester.pump();
      expect(copied, [code]);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a block with no language stays plain', (tester) async {
      await pumpApp(tester, llm: answering('```\ndef add(a, b): pass\n```'));
      await tester.pumpAndSettle();
      expect(colours(tester), hasLength(1));
    });
  });

  testWidgets('in a browser an answer carries its words for a screen reader', (
    tester,
  ) async {
    AnswerBody.labelled = true;
    addTearDown(() => AnswerBody.labelled = false);
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, llm: _server());
    expect(
      find.bySemanticsLabel(RegExp(r'^The plan\nFirst step\nSecond step')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Copy code')),
      isSemantics(label: 'Copy code', isButton: true),
    );
    semantics.dispose();
  });

  testWidgets('a model failure shows as a failure, with Retry and no Copy', (
    tester,
  ) async {
    await pumpApp(
      tester,
      llm: answering('The agent model failed to respond: 400 bad input'),
    );
    await tester.pumpAndSettle();
    expect(find.text('The model did not answer'), findsOneWidget);
    expect(
      find.text('The agent model failed to respond: 400 bad input'),
      findsOneWidget,
    );
    expect(find.byTooltip('Copy answer'), findsNothing);
    expect(find.byTooltip('Retry'), findsOneWidget);
  });

  testWidgets('a streaming answer has no Copy until it ends', (tester) async {
    final llm = _server()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    h.chat.newChat();
    await tester.pumpAndSettle();
    await h.chat.send('More?');
    llm.chat!.add(const TextChunk('**Half**'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Half', findRichText: true), findsOneWidget);
    expect(find.bySemanticsLabel('Copy answer'), findsNothing);
    await llm.chat!.close();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.bySemanticsLabel('Copy answer'), findsOneWidget);
  });

  testWidgets('reasoning is folded away and left out of Copy', (tester) async {
    final copied = _clipboard(tester);
    final llm = planningServer();
    llm.histories['budget'] = [
      const ChatMessage(role: Role.user, text: 'Colour?'),
      const ChatMessage(
        role: Role.assistant,
        text: '<think>It is a red square.</think>**red**',
      ),
    ];
    await pumpApp(tester, llm: llm);
    expect(find.text('Show reasoning'), findsOneWidget);
    expect(find.text('It is a red square.'), findsNothing);
    expect(find.textContaining('think>', findRichText: true), findsNothing);
    await tester.tap(find.text('Show reasoning'));
    await tester.pumpAndSettle();
    expect(find.text('It is a red square.'), findsOneWidget);
    expect(find.text('Hide reasoning'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Copy answer').last);
    await tester.pump();
    expect(copied, ['**red**']);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a model still reasoning says Thinking', (tester) async {
    final llm = _server()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    h.chat.newChat();
    await tester.pumpAndSettle();
    await h.chat.send('Colour?');
    llm.chat!.add(const TextChunk('<think>Hmm, a red'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Thinking…'), findsOneWidget);
    expect(find.textContaining('Hmm', findRichText: true), findsNothing);
    llm.chat!.add(const TextChunk(' square.</think>red'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Show reasoning'), findsOneWidget);
    expect(find.textContaining('red', findRichText: true), findsWidgets);
    await llm.chat!.close();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
