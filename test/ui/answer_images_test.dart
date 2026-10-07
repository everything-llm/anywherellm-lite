import 'dart:async';
import 'dart:typed_data';

import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pixels.dart';
import '../support/pump.dart';

final _card = Uri.parse('https://h:8445/_live/run/r-1.png');
final _page = Uri.parse('https://h:8445/_live/run/r-1');

/// The planning server with a card for [_card] linking to [_page] as the open chat's answer.
FakeAnythingLlm _withCard() {
  final llm = planningServer();
  llm.histories['budget'] = [
    const ChatMessage(role: Role.user, text: 'How is the run going?'),
    ChatMessage(
      role: Role.assistant,
      text: 'Here:\n\n[![Run]($_card)]($_page)',
    ),
  ];
  return llm;
}

/// The bytes of the answer image on screen.
Uint8List _shown(WidgetTester tester) =>
    (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes;

/// Pumps until a frame [live] was given reaches the screen: it comes through microtasks after
/// the first pump has drawn.
Future<void> _arrives(
  WidgetTester tester,
  StreamController<List<int>> live,
  List<int> frame,
) async {
  live.add(frame);
  await tester.pump();
  await tester.pump();
}

int _reads(FakeAnythingLlm llm) =>
    llm.calls.where((c) => c == 'answerImage:$_card').length;

void main() {
  testWidgets('a live card shows each new frame and opens its page', (
    tester,
  ) async {
    final live = StreamController<List<int>>.broadcast();
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

    // The test's image never decodes, so it has no size to tap: call the link around it.
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
    expect(h.opened, [_page]);
  });

  testWidgets('a card that cannot be read shows its description', (
    tester,
  ) async {
    await pumpApp(tester, llm: _withCard());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.text('[Run: h]'), findsOneWidget);
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
      final live = StreamController<List<int>>.broadcast();
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
    final live = StreamController<List<int>>.broadcast();
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
