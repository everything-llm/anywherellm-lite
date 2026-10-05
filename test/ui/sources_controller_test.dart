import 'package:everything/core/ports.dart';
import 'package:everything/core/upload.dart';
import 'package:everything/ui/state/sources_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
import '../support/rig.dart';

Future<Rig> started(FakeAnythingLlm llm) async {
  final rig = Rig(
    llm: llm,
    connection: sampleConnection,
    prefsStore: FakePrefsStore(),
  );
  addTearDown(rig.dispose);
  await rig.start();
  return rig;
}

UploadFile file(String name) =>
    UploadFile(name: name, read: () async => [1, 2, 3]);

void main() {
  test('lists the workspace\'s files, on', () async {
    final rig = await started(planningServer());
    expect(rig.sources.files.map((f) => (f.title, f.on)), [
      ('Q3 roadmap.pdf', true),
      ('Customer interviews.docx', true),
    ]);
    expect(rig.sources.onCount, 2);
  });

  test('switching off unembeds the file and keeps it listed', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await rig.sources.toggle(rig.sources.files.first);
    expect(
      llm.calls,
      contains('updateEmbeddings:+-custom-documents/Q3 roadmap.pdf.json'),
    );
    expect(rig.sources.files.map((f) => (f.title, f.on)), [
      ('Customer interviews.docx', true),
      ('Q3 roadmap.pdf', false),
    ]);
    expect(rig.prefsStore.saved.offIn('q3').single.title, 'Q3 roadmap.pdf');

    await rig.sources.toggle(rig.sources.files.last);
    expect(rig.sources.files.every((f) => f.on), isTrue);
    expect(rig.prefsStore.saved.offIn('q3'), isEmpty);
  });

  test('an added file is uploaded and embedded', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await rig.sources.upload([file('notes.md')]);
    expect(
      llm.calls,
      containsAllInOrder([
        'upload:notes.md',
        'updateEmbeddings:+custom-documents/notes.md.json-',
      ]),
    );
    expect(rig.sources.files.last.title, 'notes.md');
    expect(rig.chat.docCounts['q3'], 3);
  });

  test(
    'a file of a type the server does not read is refused, and the rest go',
    () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.sources.upload([file('tool.exe'), file('b.txt')]);
      expect(rig.sources.problems.single.title, 'Could not add tool.exe');
      expect(llm.calls, contains('upload:b.txt'));
      expect(llm.calls, isNot(contains('upload:tool.exe')));
    },
  );

  // testWidgets for its fake clock, which the undo and flash timers run on.
  testWidgets('removing offers undo for a few seconds', (tester) async {
    final rig = await started(planningServer());
    final first = rig.sources.files.first;
    await rig.sources.remove(first);
    expect(rig.sources.removed, same(first));
    expect(rig.sources.files, hasLength(1));

    await rig.sources.undo();
    expect(rig.sources.removed, isNull);
    expect(rig.sources.files, hasLength(2));

    await rig.sources.remove(rig.sources.files.first);
    await tester.pump(SourcesController.undoFor);
    expect(rig.sources.removed, isNull);
  });

  testWidgets('a citation lights its file for a moment', (tester) async {
    final rig = await started(planningServer());
    rig.sources.flash('Q3 roadmap.pdf');
    expect(rig.sources.flashed, 'custom-documents/Q3 roadmap.pdf.json');
    await tester.pump(SourcesController.flashFor);
    expect(rig.sources.flashed, isNull);
    rig.sources.flash('gone.pdf');
    expect(rig.sources.flashed, isNull);
  });

  test('a failed switch says why', () async {
    final llm = planningServer()
      ..errors['updateEmbeddings'] = const ApiException('busy');
    final rig = await started(llm);
    await rig.sources.toggle(rig.sources.files.first);
    expect(rig.sources.problems.single.text, 'busy');
    expect(rig.sources.files.first.on, isTrue);
  });

  test('another workspace shows its own files', () async {
    final rig = await started(planningServer());
    await rig.chat.select('household');
    await pumpEventQueue();
    expect(rig.sources.files, isEmpty);
  });
}
