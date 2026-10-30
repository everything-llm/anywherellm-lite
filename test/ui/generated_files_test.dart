import 'package:anywherellm/core/outputs.dart';
import 'package:anywherellm/ui/chat/generated_files.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pixels.dart';
import '../support/pump.dart';

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
    expect(find.text('Saved report.pdf'), findsNothing);
    await tester.tap(control('Save report.pdf'));
    await tester.pumpAndSettle();
    expect(h.saved['report.pdf'], [37, 80, 68, 70]);
    // Save keeps its label, and a line under the card says it was saved.
    expect(control('Save report.pdf'), findsOneWidget);
    expect(find.text('Saved report.pdf'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Saved report.pdf')).dy,
      greaterThan(tester.getBottomLeft(find.text('report.pdf')).dy),
    );
    expect(find.textContaining('Downloads'), findsNothing);
  });

  testWidgets('a file the server no longer has says so', (tester) async {
    final llm = planningServer()..made = const [_report];
    final h = await pumpApp(tester, llm: llm);
    await ask(tester, 'Make me a report');
    await tester.tap(control('Save report.pdf'));
    await tester.pumpAndSettle();
    expect(h.saved, isEmpty);
    expect(find.text('Saved report.pdf'), findsNothing);
    expect(find.text('Could not get report.pdf'), findsOneWidget);
    expect(find.text('File not found'), findsOneWidget);
  });

  testWidgets('an image an agent made shows, read once, and downloads', (
    tester,
  ) async {
    final llm = planningServer()
      ..made = const [_cat]
      ..generated['img-1.png'] = pixel;
    final h = await pumpApp(tester, llm: llm);
    await ask(tester, 'Draw a cat');
    expect(
      find.byWidgetPredicate((w) => w is Image && w.semanticLabel == 'cat.png'),
      findsOneWidget,
    );
    expect(find.textContaining('Image · PNG'), findsOneWidget);
    await tester.tap(control('Save cat.png'));
    await tester.pumpAndSettle();
    expect(h.saved['cat.png'], pixel);
    expect(find.text('Saved cat.png'), findsOneWidget);
    expect(
      llm.calls.where((c) => c == 'generatedFile:img-1.png'),
      hasLength(1),
    );
  });

  testWidgets('a tapped image opens over the window, to save or share', (
    tester,
  ) async {
    final llm = planningServer()
      ..made = const [_cat]
      ..generated['img-1.png'] = pixel;
    final h = await pumpApp(tester, llm: llm, canShare: true);
    await ask(tester, 'Draw a cat');
    expect(tester.takeException(), isNull);
    // The image decodes outside the test's clock, so it has no size to tap.
    tester.widget<Tappable>(control('Open cat.png')).onTap!();
    await tester.pumpAndSettle();
    final viewer = find.byType(ImageViewer);
    expect(viewer, findsOneWidget);
    await tester.tap(find.descendant(of: viewer, matching: control('Share')));
    await tester.pumpAndSettle();
    expect(h.shared['cat.png'], pixel);
    await tester.tap(find.descendant(of: viewer, matching: control('Save')));
    await tester.pumpAndSettle();
    expect(h.saved['cat.png'], pixel);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewer), findsNothing);
  });

  testWidgets(
    'a made file saves and shares under a name that stays in its folder',
    (tester) async {
      final llm = planningServer()
        ..made = const [
          GeneratedFile(
            type: 'PdfFileDownload',
            name: '../../files/prefs.json',
            storageName: 'pdf-1.pdf',
          ),
          GeneratedFile(
            type: 'imageGenerationCard',
            name: '../cat.png',
            storageName: 'img-1.png',
          ),
        ]
        ..generated['pdf-1.pdf'] = [37, 80, 68, 70]
        ..generated['img-1.png'] = pixel;
      final h = await pumpApp(tester, llm: llm, canShare: true);
      await ask(tester, 'Make me a report and a cat');
      await tester.tap(control('Save ../../files/prefs.json'));
      await tester.pumpAndSettle();
      expect(h.saved.keys, ['..-..-files-prefs.json']);
      tester.widget<Tappable>(control('Open ../cat.png')).onTap!();
      await tester.pumpAndSettle();
      final viewer = find.byType(ImageViewer);
      await tester.tap(find.descendant(of: viewer, matching: control('Share')));
      await tester.pumpAndSettle();
      expect(h.shared.keys, ['..-cat.png']);
    },
  );

  testWidgets('without a share sheet there is no Share', (tester) async {
    final llm = planningServer()
      ..made = const [_cat]
      ..generated['img-1.png'] = pixel;
    await pumpApp(tester, llm: llm);
    await ask(tester, 'Draw a cat');
    expect(find.byTooltip('Share cat.png'), findsNothing);
    tester.widget<Tappable>(control('Open cat.png')).onTap!();
    await tester.pumpAndSettle();
    expect(control('Share'), findsNothing);
    await tester.tap(
      find.descendant(of: find.byType(ImageViewer), matching: control('Close')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewer), findsNothing);
  });

  testWidgets('an image that cannot be read becomes a file card', (
    tester,
  ) async {
    final llm = planningServer()..made = const [_cat];
    await pumpApp(tester, llm: llm);
    await ask(tester, 'Draw a cat');
    expect(control('Save cat.png'), findsOneWidget);
    expect(find.text('Could not get cat.png'), findsOneWidget);
  });

  testWidgets('Edit puts a question back in the composer, sending nothing', (
    tester,
  ) async {
    final llm = planningServer();
    await pumpApp(tester, llm: llm);
    // A long press on a question is Edit.
    await tester.longPress(find.text('What is the budget?'));
    await tester.pump();
    expect(
      tester.widget<EditableText>(composerField).controller.text,
      'What is the budget?',
    );
    expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
  });

  testWidgets('Ask again is in the last answer\'s sheet, and asks again', (
    tester,
  ) async {
    final llm = planningServer()..answer = 'About 45k.';
    await pumpApp(tester, llm: llm);
    await ask(tester, 'And next year?');
    await tester.tap(control('More: read aloud, ask again, details'));
    await tester.pumpAndSettle();
    await tester.tap(control('Ask again'));
    await tester.pumpAndSettle();
    expect(llm.calls.where((c) => c.startsWith('streamChat')), [
      'streamChat:budget:And next year?',
      'streamChat:budget:And next year?',
    ]);
    expect(find.text('And next year?'), findsOneWidget);
  });
}
