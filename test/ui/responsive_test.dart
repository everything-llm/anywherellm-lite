import 'dart:ui' show Size;

import 'package:everything/core/server_models.dart';
import 'package:everything/ui/state/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// One width per shell layout, and the window's own minimum (see my_application.cc).
const sizes = [
  Size(1400, 900),
  Size(1000, 700),
  Size(780, 700),
  Size(500, 700),
  Size(360, 480),
];

const longWord =
    'an-extremely-long-unbroken-name-that-has-no-place-to-wrap-and-must-not-overflow-anything';

/// Data that stresses every layout: long unbroken names, a long chat and long files.
FakeAnythingLlm awkward() {
  final llm = FakeAnythingLlm();
  llm.spaces = [
    FakeWorkspace(
      'w',
      'name-$longWord',
      threads: [Thread(slug: 't', name: 'chat-$longWord')],
      docs: [libraryDoc(llm, 'file-$longWord.pdf', words: 123456)],
    ),
  ];
  llm.histories['t'] = [
    ChatMessage(role: Role.user, text: 'question-$longWord ' * 3),
    ChatMessage(
      role: Role.assistant,
      text: 'An answer that keeps going. ' * 40,
      citations: ['file-$longWord.pdf', 'gone-$longWord.md'],
    ),
  ];
  return llm;
}

void main() {
  for (final size in sizes) {
    final at = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('a long chat fits at $at', (tester) async {
      await pumpApp(tester, llm: awkward(), size: size);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the open drawers and Settings fit at $at', (tester) async {
      final h = await pumpApp(tester, llm: awkward(), size: size);
      h.shell
        ..toggleSide()
        ..openSources();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      h.shell.openSettings();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a draft and the no-key banner fit at $at', (tester) async {
      final h = await pumpApp(tester, llm: awkward(), size: size);
      h.chat.newChat();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await h.settings.clear();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in sizes) {
    final at = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('Files and each kind of node fit at $at', (tester) async {
      final llm = awkward();
      llm.spaces.first.prompt = 'prompt-$longWord';
      final h = await pumpApp(tester, llm: llm, size: size);
      h.shell
        ..showPane(Pane.files)
        ..toggleSide();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final path in [
        '/workspaces/w',
        '/workspaces/w/docs',
        '/workspaces/w/chats',
        '/library/custom-documents',
      ]) {
        h.files.toggle(path);
      }
      for (final path in [
        '/workspaces/w',
        '/workspaces/w/docs',
        '/workspaces/w/PROMPT.md',
        '/workspaces/w/settings.json',
        '/workspaces/w/chats/t',
        '/workspaces/w/docs/custom-documents/file-$longWord.pdf.json',
        '/library',
        '/library/custom-documents',
        '/library/custom-documents/file-$longWord.pdf.json',
        '/settings/models.json',
        '/keys',
      ]) {
        await h.files.select(path);
        await tester.pumpAndSettle();
        expect(h.files.node, isNotNull, reason: path);
        expect(tester.takeException(), isNull, reason: path);
      }
    });
  }

  testWidgets('resizing through every layout keeps working', (tester) async {
    final h = await pumpApp(tester, llm: awkward(), size: sizes.first);
    for (final size in [...sizes, ...sizes.reversed]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'at ${size.width}');
    }
    expect(h.chat.activeThread, 't');
  });
}
