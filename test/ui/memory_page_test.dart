import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/core/memory.dart';
import 'package:anywherellm/ui/settings/memory_page.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_toolkit.dart';
import '../support/pump.dart';

/// The planning server with saved memories for every workspace and Q3 planning's own.
FakeToolkit _remembering() {
  final llm = FakeToolkit();
  llm.globalMemories.addAll(const [
    SavedMemory(id: 1, text: 'Name is Anna.', global: true),
    SavedMemory(id: 2, text: 'Lives in Uppsala.', global: true),
  ]);
  llm.workspaceMemories['q3'] = [
    const SavedMemory(
      id: 3,
      text: 'Reports go to Maja on Fridays.',
      global: false,
    ),
  ];
  llm.workspaceMemories['household'] = [
    const SavedMemory(id: 4, text: 'The boiler is from 2019.', global: false),
  ];
  return llm;
}

Future<Harness> _openMemory(
  WidgetTester tester,
  FakeToolkit llm, {
  Size size = const Size(390, 1000),
}) async {
  final h = await pumpApp(
    tester,
    llm: planningServer(),
    toolkitServer: llm,
    size: size,
  );
  h.shell.openSettings(SettingsPage.memory);
  await tester.pumpAndSettle();
  return h;
}

Finder _inPage(Finder finder) =>
    find.descendant(of: find.byType(MemoryPage), matching: finder);

/// The field whose hint is [hint].
Finder _field(String hint) => _inPage(
  find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint,
  ),
);

const _memoryHint = 'One short fact, such as: Prefers metric units.';

void main() {
  testWidgets('the page lists the saved memories of the open workspace', (
    tester,
  ) async {
    await _openMemory(tester, _remembering());
    for (final text in [
      'Name is Anna.',
      'Lives in Uppsala.',
      'Reports go to Maja on Fridays.',
    ]) {
      expect(_inPage(find.text(text)), findsOneWidget, reason: text);
    }
    // Household's own memory is not Q3 planning's.
    expect(find.text('The boiler is from 2019.'), findsNothing);
    expect(find.textContaining('2 OF 5'), findsOneWidget);
  });

  testWidgets('a memory added for every workspace is saved there', (
    tester,
  ) async {
    final llm = _remembering();
    await _openMemory(tester, llm);
    await tapVisible(tester, control('Add a memory').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      _field(_memoryHint),
      '  Works from home on Mondays. ',
    );
    await tapVisible(tester, control('Add'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('addMemory:Works from home on Mondays.'));
    expect(llm.globalMemories.last.text, 'Works from home on Mondays.');
    expect(_inPage(find.text('Works from home on Mondays.')), findsOneWidget);
    expect(_field(_memoryHint), findsNothing);
  });

  testWidgets('a full list says so and takes no more', (tester) async {
    final llm = _remembering();
    llm.globalMemories.addAll([
      for (var id = 10; id < 13; id++)
        SavedMemory(id: id, text: 'Fact $id.', global: true),
    ]);
    await _openMemory(tester, llm);
    expect(
      find.text('All $globalMemoryLimit in use. Delete one to add another.'),
      findsOneWidget,
    );
    // Moving a workspace's memory there is refused before it is sent.
    await tapVisible(
      tester,
      control('Reports go to Maja on Fridays. Change or delete'),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, _inPage(find.text('Every workspace')));
    await tester.pumpAndSettle();
    await tapVisible(tester, control('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Delete one first'), findsOneWidget);
    expect(llm.calls.where((c) => c.startsWith('moveMemory')), isEmpty);
  });

  testWidgets('a memory is edited, moved to every workspace and deleted', (
    tester,
  ) async {
    final llm = _remembering();
    await _openMemory(tester, llm);
    await tapVisible(
      tester,
      control('Reports go to Maja on Fridays. Change or delete'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_field(_memoryHint), 'Reports go to Maja.');
    await tapVisible(tester, _inPage(find.text('Every workspace')));
    await tester.pumpAndSettle();
    await tapVisible(tester, control('Save'));
    await tester.pumpAndSettle();
    expect(llm.calls, containsAll(['editMemory:3', 'moveMemory:3:global']));
    expect(llm.globalMemories.last.text, 'Reports go to Maja.');
    expect(llm.workspaceMemories['q3'], isEmpty);

    await tapVisible(tester, control('Reports go to Maja. Change or delete'));
    await tester.pumpAndSettle();
    await tapVisible(tester, control('Delete'));
    await tester.pumpAndSettle();
    expect(
      find.text('Delete this memory? Chats are no longer shown it.'),
      findsOneWidget,
    );
    await tapVisible(tester, control('Delete'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('deleteMemory:3'));
    expect(find.text('Reports go to Maja.'), findsNothing);
  });

  testWidgets('saved memories switched off are not listed', (tester) async {
    final llm = _remembering();
    await _openMemory(tester, llm);
    await tapVisible(tester, control('Saved memories'));
    await tester.pumpAndSettle();
    expect(llm.switches.enabled, isFalse);
    expect(
      find.text('Off: chats are shown no saved memories, and none are saved.'),
      findsOneWidget,
    );
    expect(find.text('Name is Anna.'), findsNothing);
    expect(control('Learn from chats'), findsNothing);
  });

  testWidgets('another workspace shows its own memories', (tester) async {
    await _openMemory(tester, _remembering());
    await tapVisible(tester, control('Workspace: Q3 planning. Choose another'));
    await tester.pumpAndSettle();
    await tester.tap(control('Household'));
    await tester.pumpAndSettle();
    expect(_inPage(find.text('The boiler is from 2019.')), findsOneWidget);
    expect(find.text('Reports go to Maja on Fridays.'), findsNothing);
  });

  testWidgets('a failed read says why', (tester) async {
    final llm = _remembering()
      ..errors['memorySwitches'] = const ApiException(
        'This needs the server password. Add it in Settings.',
        status: 401,
      );
    await _openMemory(tester, llm);
    expect(find.text('Could not read the saved memories'), findsOneWidget);
    expect(find.textContaining('Add it in Settings'), findsOneWidget);
  });

  testWidgets('on a phone, Settings and a workspace\'s page open Memory', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      llm: planningServer(),
      toolkitServer: _remembering(),
    );
    h.shell.openSettings();
    await tester.pumpAndSettle();
    await tapVisible(tester, control('Memory'));
    await tester.pumpAndSettle();
    expect(find.byType(MemoryPage), findsOneWidget);
    expect(_inPage(find.text('Name is Anna.')), findsOneWidget);
    h.shell.closeSettings();
    await tester.pumpAndSettle();

    await h.chat.select('household');
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await tapVisible(tester, control('Memory, What chats are shown'));
    await tester.pumpAndSettle();
    expect(_inPage(find.text('The boiler is from 2019.')), findsOneWidget);
  });
}
