import 'dart:async';
import 'dart:typed_data';

import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pixels.dart';
import '../support/pump.dart';

final _card = Uri.parse('https://h:8445/_live/run/r-1.png');
final _page = Uri.parse('https://h:8445/_live/run/r-1');

FakeAnythingLlm _withCard() => answering('Here:\n\n[![Run]($_card)]($_page)');

/// The bytes of the answer image on screen.
Uint8List _shown(WidgetTester tester) =>
    (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes;

/// Gives [frame] to [live] and pumps until it is on screen.
Future<void> _arrives(
  WidgetTester tester,
  StreamController<Uint8List> live,
  Uint8List frame,
) async {
  live.add(frame);
  for (var i = 0; i < 5; i++) {
    await tester.pump();
    final images = find.byType(Image).evaluate();
    if (images.isNotEmpty && identical(_shown(tester), frame)) return;
  }
  fail('the frame did not show');
}

int _reads(FakeAnythingLlm llm) =>
    llm.calls.where((c) => c == 'answerImage:$_card').length;

/// Taps the card shown. The test's image never decodes, so it has no size to tap: this calls
/// the link around it.
Future<void> _tapCard(WidgetTester tester) async {
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
  testWidgets('a live card shows each new frame and opens its page', (
    tester,
  ) async {
    final live = StreamController<Uint8List>.broadcast();
    addTearDown(live.close);
    final llm = _withCard()..liveImages[_card] = live;
    final h = await pumpApp(tester, llm: llm);
    await tester.pump();
    expect(live.hasListener, isTrue);
    expect(find.byType(Image), findsNothing);

    await _arrives(tester, live, pixel);
    expect(_shown(tester), pixel);

    await _arrives(tester, live, redPixel);
    expect(_shown(tester), redPixel);

    await _tapCard(tester);
    expect(h.opened, [_page]);
  });

  testWidgets('a card whose description holds an address is still a card', (
    tester,
  ) async {
    final card = Uri.parse(
      'https://h:8445/_live/browser/bw-3aeecef2b460eeb7.jpg',
    );
    final page = Uri.parse('https://h:8445/_live/browser/bw-3aeecef2b460eeb7');
    final llm = answering(
      'Card: [![Browser: https://mail.example/un/v2/sh/WCPx]($card)]($page)',
    )..images[card] = [pixel];
    final h = await pumpApp(tester, llm: llm);
    await tester.pumpAndSettle();
    expect(_shown(tester), pixel);
    expect(find.textContaining('mail.example'), findsNothing);

    await _tapCard(tester);
    expect(h.opened, [page]);
  });

  testWidgets('a card that cannot be read shows its description', (
    tester,
  ) async {
    await pumpApp(tester, llm: _withCard());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.text('[Run: did not load]'), findsOneWidget);
    expect(
      find.byTooltip('The image could not be read: the server answered 404.'),
      findsOneWidget,
    );
  });

  testWidgets('a card that did not load opens the link around it', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: _withCard());
    await tester.pumpAndSettle();
    await tester.tap(find.text('[Run: did not load]'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(h.opened, [_page]);
  });

  testWidgets('an image outside a link opens its own address', (tester) async {
    final chart = Uri.parse('https://h:8445/_cards/chart.png');
    final h = await pumpApp(
      tester,
      llm: answering('Here:\n\n![Chart]($chart)'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('[Chart: did not load]'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(h.opened, [chart]);
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

  testWidgets('a plain card is read once, and shown again without asking', (
    tester,
  ) async {
    final llm = _withCard()..images[_card] = [pixel];
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

  testWidgets(
    'a live card is let go of while Files shows, and read again after',
    (tester) async {
      final live = StreamController<Uint8List>.broadcast();
      addTearDown(live.close);
      final llm = _withCard()..liveImages[_card] = live;
      final h = await pumpApp(tester, llm: llm);
      await tester.pump();
      live.add(pixel);
      await tester.pump();
      expect(live.hasListener, isTrue);

      h.shell.showPane(Pane.files);
      await tester.pump();
      expect(live.hasListener, isFalse);

      h.shell.showPane(Pane.chats);
      await tester.pump();
      expect(live.hasListener, isTrue);
      expect(_shown(tester), pixel);
      expect(_reads(llm), 2);
    },
  );

  testWidgets('a live card is let go of while the app is hidden', (
    tester,
  ) async {
    final live = StreamController<Uint8List>.broadcast();
    addTearDown(live.close);
    await pumpApp(tester, llm: _withCard()..liveImages[_card] = live);
    await tester.pump();
    expect(live.hasListener, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(live.hasListener, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(live.hasListener, isTrue);
  });
}
