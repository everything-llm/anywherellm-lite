import 'dart:convert';

import 'package:anywherellm/core/outputs.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

Finder control(String label) => find.byWidgetPredicate(
  (widget) => widget is Tappable && widget.label == label,
);

const _report = GeneratedFile(
  type: 'PdfFileDownload',
  name: 'report.pdf',
  storageName: 'pdf-1.pdf',
  size: 2048,
);

const _cat = GeneratedFile(
  type: 'imageGenerationCard',
  name: 'cat.png',
  storageName: 'img-1.png',
);

/// A one-pixel PNG.
final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAwS2OUAAAAABJRU5ErkJggg==',
);

Future<void> ask(WidgetTester tester, String text) async {
  await tester.enterText(composerField, text);
  await tester.pump();
  await tester.tap(control('Send'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a file an agent made downloads once a place is chosen', (
    tester,
  ) async {
    final llm = planningServer()
      ..made = const [_report]
      ..generated['pdf-1.pdf'] = [37, 80, 68, 70];
    final h = await pumpApp(tester, llm: llm);
    await ask(tester, 'Make me a report');
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(llm.calls, isNot(contains('generatedFile:pdf-1.pdf')));
    await tester.tap(control('Download report.pdf'));
    await tester.pumpAndSettle();
    expect(h.saved['report.pdf'], [37, 80, 68, 70]);
  });

  testWidgets(
    'an answer shows how it ran, and one not measured shows nothing',
    (tester) async {
      final llm = planningServer();
      await pumpApp(tester, llm: llm);
      await ask(tester, 'First');
      expect(find.textContaining('tokens'), findsNothing);
      llm.measured = const AnswerMetrics(model: 'glm-5.3', tokens: 1642);
      await ask(tester, 'Second');
      expect(find.text('glm-5.3 · 1,642 tokens'), findsOneWidget);
    },
  );

  testWidgets('a file the server no longer has says so', (tester) async {
    final llm = planningServer()..made = const [_report];
    final h = await pumpApp(tester, llm: llm);
    await ask(tester, 'Make me a report');
    await tester.tap(control('Download report.pdf'));
    await tester.pumpAndSettle();
    expect(h.saved, isEmpty);
    expect(find.text('Could not get report.pdf'), findsOneWidget);
    expect(find.text('File not found'), findsOneWidget);
  });

  testWidgets('an image an agent made shows, read once, and downloads', (
    tester,
  ) async {
    final llm = planningServer()
      ..made = const [_cat]
      ..generated['img-1.png'] = _pixel;
    final h = await pumpApp(tester, llm: llm);
    await ask(tester, 'Draw a cat');
    expect(
      find.byWidgetPredicate((w) => w is Image && w.semanticLabel == 'cat.png'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Download cat.png'));
    await tester.pumpAndSettle();
    expect(h.saved['cat.png'], _pixel);
    expect(
      llm.calls.where((c) => c == 'generatedFile:img-1.png'),
      hasLength(1),
    );
  });

  testWidgets('an image that cannot be read becomes a download chip', (
    tester,
  ) async {
    final llm = planningServer()..made = const [_cat];
    await pumpApp(tester, llm: llm);
    await ask(tester, 'Draw a cat');
    expect(control('Download cat.png'), findsOneWidget);
    expect(find.text('Could not get cat.png'), findsOneWidget);
  });
}
