import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/chat/answer_body.dart';
import 'package:anywherellm/ui/chat/markdown_lists.dart';
import 'package:anywherellm/ui/chat/wait_line.dart';
import 'package:anywherellm/ui/icons.dart';
import 'package:anywherellm/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:anywherellm/ui/widgets/controls.dart';
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

/// The gap between the foot of the [first] line's text and the top of the [second]'s.
double _gap(WidgetTester tester, String first, String second) =>
    tester.getTopLeft(find.textContaining(second)).dy -
    tester.getBottomLeft(find.textContaining(first)).dy;

void main() {
  testWidgets('a tight list sets its items line to line, a loose one apart', (
    tester,
  ) async {
    await _show(
      tester,
      'Plan:\n\n- Alpha\n- Beta\n\nThen:\n\n- Gamma\n\n- Delta',
    );
    expect(_gap(tester, 'Alpha', 'Beta'), 0);
    expect(_gap(tester, 'Gamma', 'Delta'), 8);
    expect(_gap(tester, 'Plan:', 'Alpha'), 8);
  });

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

  testWidgets(
    'a code block and display math show thin scrollbars in the line colour',
    (tester) async {
      final code = 'final total = ${List.filled(30, 'price').join(' + ')};';
      final sum = List.filled(40, 'x_i').join(' + ');
      await pumpApp(
        tester,
        llm: answering('```dart\n$code\n```\n\n\$\$$sum\$\$'),
        size: const Size(500, 800),
      );
      await tester.pumpAndSettle();
      final bars = tester.widgetList<RawScrollbar>(
        find.descendant(
          of: find.byType(AnswerBody),
          matching: find.byType(RawScrollbar),
        ),
      );
      expect(bars.where((b) => b.thumbVisibility == true), hasLength(2));
      final line = Tokens.light.lineStrong;
      for (final bar in bars) {
        expect(bar.thickness, lessThanOrEqualTo(4));
        expect(bar.thumbColor, line);
      }
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'a code block keeps its Copy button clear of the code, scrolled or not, '
      'and sits on nothing square (text at ${scale}x)',
      (tester) async {
        final code =
            'Linux agents-vm 6.12.113+deb13-cloud-amd64 #1 SMP PREEMPT_DYNAMIC '
            'Debian 6.12.113-1 (2026-10-15) x86_64 GNU/Linux';
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpApp(
          tester,
          llm: answering('Just ran it:\n\n```\n$code\n```'),
          size: const Size(320, 700),
        );
        await tester.pumpAndSettle();
        final copy = find.byTooltip('Copy code');
        final view = find.descendant(
          of: find.byType(AnswerBody),
          matching: find.byType(Scrollable),
        );
        for (final end in [false, true]) {
          if (end) {
            final scroll = tester.state<ScrollableState>(view.first).position;
            scroll.jumpTo(scroll.maxScrollExtent);
            await tester.pump();
          }
          final viewport = tester.getRect(view.first);
          expect(
            viewport.overlaps(tester.getRect(copy)),
            isFalse,
            reason: 'the code scrolls only beside the button',
          );
        }
        // Nothing behind the rounded box paints a colour of its own: the package's wrapper of a
        // code block is bare. The answer's own tile lies outside the answer's body.
        final behind = tester
            .widgetList<Container>(
              find.ancestor(
                of: copy,
                matching: find.descendant(
                  of: find.byType(AnswerBody),
                  matching: find.byType(Container),
                ),
              ),
            )
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .where((d) => d.color != null && d.color != Tokens.light.sunken);
        expect(behind, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

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
    // The icon turns to a check in place, no word pushes the row, and a live region says it.
    AppIcon iconIn(String label) => tester.widget<AppIcon>(
      find.descendant(
        of: find.bySemanticsLabel(label).last,
        matching: find.byType(AppIcon),
      ),
    );
    expect(find.text('Copied'), findsNothing);
    expect(iconIn('Copy answer').name, 'check');
    expect(find.bySemanticsLabel('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.bySemanticsLabel('Copied'), findsNothing);
    expect(iconIn('Copy answer').name, 'copy');
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

  testWidgets('a model that cannot see a picture says so, and offers another', (
    tester,
  ) async {
    await _show(
      tester,
      'The agent model failed to respond: 400 messages.content.type is invalid, '
      "allowed values: ['text']",
    );
    expect(find.text('This model cannot see pictures'), findsOneWidget);
    expect(find.text('The model did not answer'), findsNothing);
    await tester.tap(find.text('Change the model'));
    await tester.pumpAndSettle();
    expect(find.text('Applies to every chat in Q3 planning.'), findsOneWidget);
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

  testWidgets('the caret ends the text being written, but not inside code', (
    tester,
  ) async {
    final llm = _server()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    h.chat.newChat();
    await tester.pumpAndSettle();
    await h.chat.send('More?');
    llm.chat!.add(const TextChunk('The plan is'));
    await tester.pump(const Duration(milliseconds: 100));
    final line = find.textContaining('The plan is', findRichText: true);
    expect(find.descendant(of: line, matching: find.byType(Caret)), findsOne);
    expect(find.byType(Caret), findsOne);
    llm.chat!.add(const TextChunk('\n\n```\nprint(1'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining(caretMark, findRichText: true), findsNothing);
    expect(find.byType(Caret), findsOne);
    await llm.chat!.close();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Caret), findsNothing);
  });

  testWidgets('reasoning never shows, and is left out of Copy', (tester) async {
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
    expect(find.text('It is a red square.'), findsNothing);
    expect(find.textContaining('think>', findRichText: true), findsNothing);
    // An answer the server did not measure and cannot rate has no More.
    expect(find.byTooltip('More'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Copy answer').last);
    await tester.pump();
    expect(copied, ['**red**']);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a model still reasoning shows none of it', (tester) async {
    final llm = _server()..hold = true;
    final h = await pumpApp(tester, llm: llm);
    h.chat.newChat();
    await tester.pumpAndSettle();
    await h.chat.send('Colour?');
    llm.chat!.add(const TextChunk('<think>Hmm, a red'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Thinking…'), findsNothing);
    expect(find.byType(WaitLine), findsOneWidget);
    expect(find.textContaining('Hmm', findRichText: true), findsNothing);
    llm.chat!.add(const TextChunk(' square.</think>red'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Thinking…'), findsNothing);
    expect(find.textContaining('Hmm', findRichText: true), findsNothing);
    expect(find.textContaining('red', findRichText: true), findsWidgets);
    await llm.chat!.close();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets(
    'an answer follows the system text size changing while it shows',
    (tester) async {
      final dispatcher =
          TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
      addTearDown(dispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester, llm: answering('Hello there my friend'));
      await tester.pumpAndSettle();
      final answer = find.byWidgetPredicate(
        (w) => w is EditableText && w.controller.text.contains('Hello there'),
      );
      final before = tester.getSize(answer.first);
      dispatcher.textScaleFactorTestValue = 1.6;
      await tester.pumpAndSettle();
      expect(tester.getSize(answer.first).height, greaterThan(before.height));
    },
  );
}
