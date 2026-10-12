import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/core/memory.dart';
import 'package:anywherellm/ui/settings/memory_page.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// The planning server with saved memories for every workspace and Q3 planning's own, and
/// long-term facts and a file read in.
FakeAnythingLlm _remembering() {
  final llm = planningServer();
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
  llm.addFact('Prefers morning appointments.');
  llm.addFact('The Q3 budget for research is about 40k.', workspace: 'q3');
  llm.addFact('Takes coffee black.');
  llm.longFiles['q3'] = [
    const LongFile(path: '/project/interview-notes.md', parts: 12),
  ];
  return llm;
}

Future<Harness> _openMemory(
  WidgetTester tester,
  FakeAnythingLlm llm, {
  Size size = const Size(1400, 1000),
}) async {
  final h = await pumpApp(tester, llm: llm, size: size);
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
  testWidgets('the page lists both memories of the open workspace', (
    tester,
  ) async {
    await _openMemory(tester, _remembering());
    for (final text in [
      'Name is Anna.',
      'Lives in Uppsala.',
      'Reports go to Maja on Fridays.',
      'Takes coffee black.',
      'The Q3 budget for research is about 40k.',
      '/project/interview-notes.md',
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
    await tester.tap(_inPage(find.text('Every workspace')));
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
    await tester.tap(_inPage(find.text('Every workspace')));
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
    // The long-term memory is a thing apart.
    expect(_inPage(find.text('Takes coffee black.')), findsOneWidget);
  });

  testWidgets('a search finds long-term facts closest first, and one is '
      'forgotten after asking', (tester) async {
    final llm = _remembering();
    await _openMemory(tester, llm);
    await tester.enterText(_field('Find by meaning'), 'coffee');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('recallMemory:coffee'));
    expect(find.text('CLOSEST FIRST'), findsOneWidget);
    expect(find.textContaining('65% match'), findsOneWidget);
    expect(_inPage(find.text('Prefers morning appointments.')), findsNothing);

    await tapVisible(tester, control('Takes coffee black. Forget it'));
    await tester.pumpAndSettle();
    await tapVisible(tester, control('Forget'));
    await tester.pumpAndSettle();
    expect(llm.calls.where((c) => c.startsWith('forgetLong:m')), hasLength(1));
    expect(_inPage(find.text('Takes coffee black.')), findsNothing);
    expect(find.text('Nothing kept is close to that.'), findsOneWidget);
  });

  testWidgets('something remembered is kept for the workspace, and a fact '
      'already kept says so', (tester) async {
    final llm = _remembering();
    await _openMemory(tester, llm);
    await tapVisible(tester, control('Remember something'));
    await tester.pumpAndSettle();
    await tester.enterText(
      _field('One short fact, such as: Takes coffee black.'),
      'Maja prefers slides to documents.',
    );
    await tapVisible(tester, control('Remember'));
    await tester.pumpAndSettle();
    expect(llm.longFacts.first.workspace, 'q3');
    expect(
      _inPage(find.text('Maja prefers slides to documents.')),
      findsOneWidget,
    );

    await tapVisible(tester, control('Remember something'));
    await tester.pumpAndSettle();
    await tester.enterText(
      _field('One short fact, such as: Takes coffee black.'),
      'takes coffee black.',
    );
    await tapVisible(tester, control('Remember'));
    await tester.pumpAndSettle();
    expect(find.text('Already kept: Takes coffee black.'), findsOneWidget);
  });

  testWidgets('a file\'s text is forgotten after asking', (tester) async {
    final llm = _remembering();
    await _openMemory(tester, llm);
    await tapVisible(
      tester,
      control('/project/interview-notes.md. Forget its text'),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, control('Forget'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('forgetLong:/project/interview-notes.md'));
    expect(llm.longFiles['q3'], isEmpty);
  });

  testWidgets('another workspace shows its own memories', (tester) async {
    await _openMemory(tester, _remembering());
    await tapVisible(
      tester,
      _inPage(find.byType(DropdownButton<String>)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Household').last);
    await tester.pumpAndSettle();
    expect(_inPage(find.text('The boiler is from 2019.')), findsOneWidget);
    expect(find.text('Reports go to Maja on Fridays.'), findsNothing);
    expect(
      _inPage(find.text('The Q3 budget for research is about 40k.')),
      findsNothing,
    );
  });

  testWidgets('a server without the host says it has no long-term memory', (
    tester,
  ) async {
    final llm = _remembering()..noMemoryRoute = true;
    await _openMemory(tester, llm);
    expect(
      find.textContaining('This server has no long-term memory'),
      findsOneWidget,
    );
    expect(_field('Find by meaning'), findsNothing);
    expect(_inPage(find.text('Name is Anna.')), findsOneWidget);
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
      llm: _remembering(),
      size: const Size(390, 844),
    );
    h.shell.openSettings();
    await tester.pumpAndSettle();
    await tapVisible(tester, control('Memory, Saved and long-term'));
    await tester.pumpAndSettle();
    expect(find.byType(MemoryPage), findsOneWidget);
    expect(_inPage(find.text('Name is Anna.')), findsOneWidget);
    h.shell.closeSettings();
    await tester.pumpAndSettle();

    await h.chat.select('household');
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await tapVisible(
      tester,
      control('Memory, What chats are shown, and the agent can recall'),
    );
    await tester.pumpAndSettle();
    expect(_inPage(find.text('The boiler is from 2019.')), findsOneWidget);
  });
}
