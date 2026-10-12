import 'dart:async';

import 'package:anywherellm/core/files.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
import '../support/rig.dart';

Future<Rig> started(FakeAnythingLlm llm, {Prefs prefs = const Prefs()}) async {
  final rig = Rig(
    llm: llm,
    connection: sampleConnection,
    prefsStore: FakePrefsStore(prefs),
  );
  addTearDown(rig.dispose);
  await rig.start();
  await rig.files.load();
  return rig;
}

const roadmap = 'custom-documents/Q3 roadmap.pdf.json';

void main() {
  test('reads every workspace on its own', () async {
    final rig = await started(planningServer());
    final tree = rig.files.tree;
    expect(nodeAt(tree, '/workspaces/q3/PROMPT.md'), isNotNull);
    expect(nodeAt(tree, '/workspaces/household/settings.json'), isNotNull);
    expect(
      nodeAt(tree, '/workspaces/q3/docs/$roadmap')!.name,
      'Q3 roadmap.pdf',
    );
  });

  test(
    'a workspace that cannot be read says why and the rest still load',
    () async {
      final llm = planningServer()
        ..errors['workspace'] = const ApiException('down');
      final rig = Rig(llm: llm, connection: sampleConnection);
      addTearDown(rig.dispose);
      await rig.chat.load();
      await rig.files.load();
      expect(rig.files.problems.map((p) => p.title), [
        'Could not read q3',
        'Could not read household',
      ]);
    },
  );

  group('saving', () {
    test('a prompt writes it, and an empty one clears it', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.files.ensureLoaded();
      await rig.files.openSection(FilesSection.instructions);
      expect(await rig.files.save('Answer in French.'), isTrue);
      expect(llm.spaces.first.prompt, 'Answer in French.');
      expect(rig.files.text, 'Answer in French.');
      await rig.files.save('  \n');
      expect(llm.spaces.first.prompt, isNull);
    });

    test('settings write only what changed', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.files.ensureLoaded();
      await rig.files.openSection(FilesSection.answers);
      final draft = rig.files.text!.replaceFirst('"topN": 4', '"topN": 7');
      llm.calls.clear();
      expect(await rig.files.save(draft), isTrue);
      expect(llm.calls.first, 'updateWorkspace:q3');
      expect(llm.spaces.first.settings['topN'], 7);
      expect(rig.files.text, contains('"topN": 7'));
    });

    test('bad settings are refused before anything is sent', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.files.ensureLoaded();
      await rig.files.openSection(FilesSection.answers);
      final draft = rig.files.text!.replaceFirst('"automatic"', '"agent"');
      llm.calls.clear();
      expect(await rig.files.save(draft), isFalse);
      expect(llm.calls, isNot(contains('updateWorkspace:q3')));
      expect(rig.files.problems.single.text, contains('chatMode'));
    });
  });

  test('a deleted workspace leaves the tree', () async {
    final rig = await started(planningServer());
    await rig.chat.deleteWorkspace('q3');
    await pumpEventQueue();
    expect(nodeAt(rig.files.tree, '/workspaces/q3'), isNull);
  });

  test('a new server starts afresh', () async {
    final rig = await started(planningServer());
    await rig.settings.save('https://other:3001', 'K2');
    await pumpEventQueue();
    expect(nodeAt(rig.files.tree, '/workspaces/q3/PROMPT.md'), isNull);
  });

  test('a workspace made after loading is read too', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await rig.chat.createWorkspace('Travel');
    await pumpEventQueue();
    expect(nodeAt(rig.files.tree, '/workspaces/travel/PROMPT.md'), isNotNull);
  });

  test('a late failure on a forgotten server shows no problem', () async {
    final llm = planningServer()
      ..errors['updateWorkspace'] = const ApiException('No');
    final rig = await started(llm);
    await rig.files.ensureLoaded();
    await rig.files.openSection(FilesSection.instructions);
    final gate = llm.gates['updateWorkspace'] = Completer<void>();
    final saving = rig.files.save('Be brief.');
    await rig.settings.save('https://other:3001', 'K2');
    gate.complete();
    await saving;
    expect(rig.files.problems, isEmpty);
  });

  test('a late load neither restores old data nor stays busy', () async {
    final llm = planningServer();
    final rig = await started(llm);
    final gate = llm.gates['workspace'] = Completer<void>();
    final loading = rig.files.load();
    await rig.settings.clear();
    gate.complete();
    await loading;
    expect(rig.files.loading, isFalse);
    expect(rig.files.detail('q3'), isNull);
    llm.gates.remove('workspace');
    await rig.settings.save(sampleConnection.baseUrl, sampleConnection.apiKey);
    await pumpEventQueue();
    await rig.files.ensureLoaded();
    expect(rig.files.detail('q3'), isNotNull);
  });

  test(
    'the pages on screen read a new server\'s workspaces by themselves',
    () async {
      final rig = Rig(llm: planningServer(), connection: sampleConnection);
      addTearDown(rig.dispose);
      await rig.start();
      await rig.files.ensureLoaded();
      await rig.settings.save('https://other:3001', 'K2');
      await pumpEventQueue();
      expect(rig.files.detail('q3'), isNotNull);
    },
  );

  test('Read again keeps the reads that failed in view', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await rig.files.ensureLoaded();
    llm.errors['workspace'] = const ApiException('down');
    await rig.files.load();
    expect(rig.files.problems.map((p) => p.title), [
      'Could not read q3',
      'Could not read household',
    ]);
  });

  test('a change made in Sources shows here', () async {
    final rig = await started(planningServer());
    bool uses() =>
        rig.files.detail('q3')!.documents.any((d) => d.path == roadmap);
    expect(uses(), isTrue);
    final file = rig.sources.files.firstWhere((f) => f.path == roadmap);
    await rig.sources.toggle(file);
    expect(uses(), isFalse);
  });

  group('sections', () {
    test('once shown, they hold the open workspace\'s documents', () async {
      final rig = await started(planningServer());
      expect(rig.files.selected, isNull);
      await rig.files.ensureLoaded();
      expect(rig.files.selected, docsPath('q3'));
    });

    test('a section of another workspace follows it', () async {
      final rig = await started(planningServer());
      await rig.files.ensureLoaded();
      await rig.files.openSection(FilesSection.answers);
      expect(rig.files.text, contains('"chatMode"'));
      await rig.chat.select('household');
      await pumpEventQueue();
      expect(rig.files.selected, settingsPath('household'));
    });

    test('a workspace opened while the pages are hidden is followed when they show', () async {
      final rig = await started(planningServer());
      await rig.files.ensureLoaded();
      rig.files.hidden();
      await rig.chat.select('household');
      await pumpEventQueue();
      expect(rig.files.selected, docsPath('q3'));
      await rig.files.ensureLoaded();
      expect(rig.files.selected, docsPath('household'));
    });

    test('a document\'s text is read for viewing and put away', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.files.ensureLoaded();
      await rig.files.viewText(roadmap, 'Q3 roadmap.pdf');
      expect(rig.files.reading?.title, 'Q3 roadmap.pdf');
      expect(rig.files.doc?.text, 'The text of Q3 roadmap.pdf.');
      expect(llm.calls, contains('document:$roadmap'));
      rig.files.closeText();
      expect(rig.files.reading, isNull);
      expect(rig.files.doc, isNull);
    });

    test('another section puts the text away', () async {
      final rig = await started(planningServer());
      await rig.files.ensureLoaded();
      await rig.files.viewText(roadmap, 'Q3 roadmap.pdf');
      await rig.files.openSection(FilesSection.instructions);
      expect(rig.files.reading, isNull);
    });
  });
}
