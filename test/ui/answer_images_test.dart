import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pixels.dart';
import '../support/pump.dart';

final _chart = Uri.parse('https://h:3001/pictures/chart.png');
final _page = Uri.parse('https://h:3001/reports/q3');

FakeAnythingLlm _withChart() =>
    answering('Here:\n\n[![Chart]($_chart)]($_page)');

/// The bytes of the answer image on screen.
Uint8List _shown(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image)).image;
  final memory = image is ResizeImage ? image.imageProvider : image;
  return (memory as MemoryImage).bytes;
}

int _reads(FakeAnythingLlm llm) =>
    llm.calls.where((c) => c == 'answerImage:$_chart').length;

/// Taps the image shown. The test's image never decodes, so it has no size to tap: this calls
/// the link around it.
Future<void> _tapImage(WidgetTester tester) async {
  tester
      .widget<GestureDetector>(
        find
            .ancestor(
              of: find.byType(Image),
              matching: find.byType(GestureDetector),
            )
            .first,
      )
      .onTap!();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('a linked image from the server shows and opens its link', (
    tester,
  ) async {
    final source = Uri.parse('https://zoo.example/red-panda');
    final llm = answering('Red pandas:\n\n[![Red panda]($_chart)]($source)')
      ..images[_chart] = pixel;
    final h = await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    expect(_shown(tester), pixel);
    expect(llm.calls, contains('answerImage:$_chart'));
    expect(llm.calls.where((c) => c.contains('zoo.example')), isEmpty);

    await _tapImage(tester);
    expect(h.opened, [source]);
  });

  testWidgets('an image whose description holds an address is still one', (
    tester,
  ) async {
    final llm = answering(
      'Card: [![Page: https://mail.example/un/v2/sh/WCPx]($_chart)]($_page)',
    )..images[_chart] = pixel;
    final h = await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    expect(_shown(tester), pixel);
    expect(find.textContaining('mail.example'), findsNothing);
    await _tapImage(tester);
    expect(h.opened, [_page]);
  });

  testWidgets('an image that cannot be read shows its description', (
    tester,
  ) async {
    await pumpApp(tester, llm: _withChart());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.text('[Chart: did not load]'), findsOneWidget);
    expect(
      find.byTooltip('The image could not be read: the server answered 404.'),
      findsOneWidget,
    );
  });

  testWidgets('an image that did not load opens the link around it', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: _withChart());
    await tester.pumpAndSettle();
    await tester.tap(find.text('[Chart: did not load]'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(h.opened, [_page]);
  });

  testWidgets('an image outside a link opens its own address', (tester) async {
    final h = await pumpApp(
      tester,
      llm: answering('Here:\n\n![Chart]($_chart)'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('[Chart: did not load]'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(h.opened, [_chart]);
  });

  testWidgets('an image off the server is not read and says where it is', (
    tester,
  ) async {
    final elsewhere = Uri.parse('https://elsewhere.example/chart.png');
    final llm = answering('Here:\n\n![Chart]($elsewhere)');
    final h = await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    expect(llm.calls.where((c) => c.startsWith('answerImage')), isEmpty);
    expect(
      find.byTooltip(
        "Not loaded: images load only from the server's own host.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('[Chart: elsewhere.example]'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(h.opened, [elsewhere]);
  });

  testWidgets('an image is read once, and shown again without asking', (
    tester,
  ) async {
    final llm = _withChart()..images[_chart] = pixel;
    final h = await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    expect(_shown(tester), pixel);

    await h.chat.select('q3', thread: 'priorities');
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    await h.chat.select('q3', thread: 'budget');
    await tester.pumpAndSettle();
    expect(_shown(tester), pixel);
    expect(_reads(llm), 1);
  });
}
