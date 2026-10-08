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

/// Builds the app with [answer] as the open chat's last answer, and lets it settle.
Future<void> _show(WidgetTester tester, String answer) async {
  await pumpApp(tester, llm: answering(answer));
  await tester.pumpAndSettle();
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
  testWidgets('a table wider than the chat shows its scrollbar', (
    tester,
  ) async {
    final cells = [for (var i = 1; i <= 12; i++) 'Column number $i'];
    final table = [
      '| ${cells.join(' | ')} |',
      '|${' --- |' * cells.length}',
      '| ${cells.join(' | ')} |',
    ].join('\n');
    await pumpApp(tester, llm: answering(table), size: const Size(500, 800));
    await tester.pumpAndSettle();
    final bars = tester.widgetList<Scrollbar>(
      find.descendant(
        of: find.byType(AnswerBody),
        matching: find.byType(Scrollbar),
      ),
    );
    expect(bars.map((b) => b.thumbVisibility), contains(true));
  });

  testWidgets('a code block and display math show their scrollbars', (
    tester,
  ) async {
    final code = 'final total = ${List.filled(30, 'price').join(' + ')};';
    final sum = List.filled(40, 'x_i').join(' + ');
    await pumpApp(
      tester,
      llm: answering('```dart\n$code\n```\n\n\$\$$sum\$\$'),
      size: const Size(500, 800),
    );
    await tester.pumpAndSettle();
    final bars = tester.widgetList<Scrollbar>(
      find.descendant(
        of: find.byType(AnswerBody),
        matching: find.byType(Scrollbar),
      ),
    );
    expect(bars.where((b) => b.thumbVisibility == true), hasLength(2));
  });

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
      await _show(tester, r'''
Inline $x^2$ and \(y\).

$$\frac{a}{b}$$

\[ z = 1 \]''');
      expect(find.byType(Math), findsNWidgets(4));
    });

    testWidgets('the same TeX twice is drawn twice', (tester) async {
      await _show(tester, r'Let $x$ be one, and $x$ again.');
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('prices stay text', (tester) async {
      await _show(tester, r'It costs $5 and $10 a month.');
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
      await _show(tester, r'Run `echo $HOME$` now.');
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('TeX that does not parse shows its source', (tester) async {
      await _show(tester, r'Broken: $\frac{a$ here.');
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
      await _show(tester, '```python\n$code\n```');
      expect(colours(tester).length, greaterThan(1));
      await tester.tap(find.bySemanticsLabel('Copy code'));
      await tester.pump();
      expect(copied, [code]);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a block with no language stays plain', (tester) async {
      await _show(tester, '```\ndef add(a, b): pass\n```');
      expect(colours(tester), hasLength(1));
    });
  });

  testWidgets('in a browser an answer carries its words for a screen reader', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, llm: _server(), labelAnswers: true);
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

  testWidgets('an answer is labelled only once it has finished', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm, labelAnswers: true);
    await h.chat.send('Go');
    llm.chat!.add(const TextChunk('Words so far'));
    await tester.pump(const Duration(milliseconds: 100));
    final label = find.bySemanticsLabel('Words so far');
    expect(label, findsNothing);
    llm.chat!.add(const ChatDone([]));
    await llm.chat!.close();
    await tester.pump(const Duration(milliseconds: 100));
    expect(label, findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a model failure shows as a failure, with Retry and no Copy', (
    tester,
  ) async {
    await _show(tester, 'The agent model failed to respond: 400 bad input');
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

  testWidgets('reasoning is hidden until More shows it, and left out of Copy', (
    tester,
  ) async {
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
    expect(find.text('Show reasoning'), findsNothing);
    expect(find.text('It is a red square.'), findsNothing);
    expect(find.textContaining('think>', findRichText: true), findsNothing);
    // An answer the server did not measure still has More, for its reasoning alone.
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Show details under every answer'), findsNothing);
    await tester.tap(find.text('View reasoning'));
    await tester.pumpAndSettle();
    expect(find.text('View reasoning'), findsNothing);
    expect(find.text('It is a red square.'), findsOneWidget);
    await tester.tap(find.text('Hide reasoning'));
    await tester.pumpAndSettle();
    expect(find.text('It is a red square.'), findsNothing);
    expect(find.text('Hide reasoning'), findsNothing);
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
    expect(find.text('Thinking…'), findsNothing);
    expect(find.textContaining('Hmm', findRichText: true), findsNothing);
    expect(find.textContaining('red', findRichText: true), findsWidgets);
    await llm.chat!.close();
    await tester.pump(const Duration(milliseconds: 100));
  });
}
