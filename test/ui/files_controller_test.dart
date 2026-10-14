import 'dart:async';

import 'package:anywherellm/core/files.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
import '../support/settings_text.dart';
import '../support/rig.dart';

Future<Rig> started(FakeAnythingLlm llm, {Prefs prefs = const Prefs()}) async {
  final rig = Rig(
    llm: llm,
    connection: sampleConnection,
    prefsStore: FakePrefsStore(prefs),
  );
  addTearDown(rig.dispose);
  await rig.start();
  await pumpEventQueue();
  return rig;
}

const roadmap = 'custom-documents/Q3 roadmap.pdf.json';

void main() {
  test('takes the open workspace as Sources reads it', () async {
    final rig = await started(planningServer());
    final q3 = rig.files.detail('q3')!;
    expect(q3.settings, isNotNull);
    expect(q3.documents.map((d) => d.path), contains(roadmap));
    expect(rig.files.detail('household'), isNull);
  });

  group('saving', () {
    test('a prompt writes it, and an empty one clears it', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.files.ensureLoaded();
      await rig.files.openSection(FilesSection.instructions);
      expect(await rig.files.save('Answer in French.'), isTrue);
      expect(llm.spaces.first.prompt, 'Answer in French.');
      expect(rig.files.detail('q3')!.prompt, 'Answer in French.');
      await rig.files.save('  \n');
      expect(llm.spaces.first.prompt, isNull);
    });

    test('settings write only what changed', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.files.ensureLoaded();
      await rig.files.openSection(FilesSection.answers);
      final draft = settingsText(rig.files.detail('q3')!.settings!)
          .replaceFirst('"topN": 4', '"topN": 7');
      llm.calls.clear();
      expect(await rig.files.save(draft), isTrue);
      expect(llm.calls.first, 'updateWorkspace:q3');
      expect(llm.spaces.first.settings['topN'], 7);
      expect(rig.files.detail('q3')!.settings!.values['topN'], 7);
    });

    test('bad settings are refused before anything is sent', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.files.ensureLoaded();
      await rig.files.openSection(FilesSection.answers);
      final draft = settingsText(rig.files.detail('q3')!.settings!)
          .replaceFirst('"automatic"', '"agent"');
      llm.calls.clear();
      expect(await rig.files.save(draft), isFalse);
      expect(llm.calls, isNot(contains('updateWorkspace:q3')));
      expect(rig.files.problems.single.text, contains('chatMode'));
    });
  });

  test('a deleted workspace is forgotten', () async {
    final rig = await started(planningServer());
    await rig.chat.deleteWorkspace('q3');
    await pumpEventQueue();
    expect(rig.files.detail('q3'), isNull);
  });

  test('a new server starts afresh', () async {
    final rig = await started(planningServer());
    rig.llm.gates['workspace'] = Completer<void>();
    await rig.settings.save('https://other:3001', 'K2');
    await pumpEventQueue();
    expect(rig.files.detail('q3'), isNull);
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

  test(
    'the pages on screen take a new server\'s workspace by themselves',
    () async {
      final rig = await started(planningServer());
      await rig.files.ensureLoaded();
      await rig.settings.save('https://other:3001', 'K2');
      await pumpEventQueue();
      expect(rig.files.detail('q3'), isNotNull);
      expect(rig.files.workspace, 'q3');
    },
  );

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
      expect(rig.files.workspace, isNull);
      await rig.files.ensureLoaded();
      expect(rig.files.workspace, 'q3');
    });

    test('a section of another workspace follows it', () async {
      final rig = await started(planningServer());
      await rig.files.ensureLoaded();
      await rig.files.openSection(FilesSection.answers);
      await rig.chat.select('household');
      await pumpEventQueue();
      expect(rig.files.workspace, 'household');
      expect(rig.files.section, FilesSection.answers);
    });

    test('a workspace opened while the pages are hidden is followed when they show', () async {
      final rig = await started(planningServer());
      await rig.files.ensureLoaded();
      rig.files.hidden();
      await rig.chat.select('household');
      await pumpEventQueue();
      expect(rig.files.workspace, 'q3');
      await rig.files.ensureLoaded();
      expect(rig.files.workspace, 'household');
    });

    test('a document\'s text is read for viewing and put away', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.files.ensureLoaded();
      await rig.files.viewText(roadmap, 'Q3 roadmap.pdf');
      expect(rig.files.reading?.title, 'Q3 roadmap.pdf');
      expect(rig.files.text, 'The text of Q3 roadmap.pdf.');
      expect(llm.calls, contains('document:$roadmap'));
      rig.files.closeText();
      expect(rig.files.reading, isNull);
      expect(rig.files.text, isNull);
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
