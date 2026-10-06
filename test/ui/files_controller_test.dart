import 'package:anywherellm/core/files.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/upload.dart';
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
  test('reads every workspace on its own and the library', () async {
    final rig = await started(planningServer());
    final tree = rig.files.tree;
    expect(nodeAt(tree, '/workspaces/q3/PROMPT.md'), isNotNull);
    expect(nodeAt(tree, '/workspaces/household/settings.json'), isNotNull);
    expect(
      nodeAt(tree, '/workspaces/q3/docs/$roadmap')!.name,
      'Q3 roadmap.pdf',
    );
    expect(nodeAt(tree, '/library/$roadmap'), isNotNull);
    expect(rig.files.usersOf(roadmap).map((w) => w.slug), ['q3']);
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
      expect(nodeAt(rig.files.tree, '/library/$roadmap'), isNotNull);
    },
  );

  test('selecting a file reads its text', () async {
    final llm = planningServer();
    llm.spaces.first.prompt = 'Be brief.';
    final rig = await started(llm);
    await rig.files.select('/workspaces/q3/PROMPT.md');
    expect(rig.files.text, 'Be brief.');
    await rig.files.select('/workspaces/q3/chats/budget');
    expect(rig.files.text, startsWith('# Budget questions\n'));
    expect(rig.files.text, contains('Sources: Q3 roadmap.pdf'));
    await rig.files.select('/settings/models.json');
    expect(rig.files.text, contains('"LLMProvider": "ollama"'));
    await rig.files.select('/library/$roadmap');
    expect(rig.files.doc!.text, 'The text of Q3 roadmap.pdf.');
    await rig.files.select('/.env');
    expect((rig.files.text, rig.files.doc), (null, null));
  });

  group('saving', () {
    test('a prompt writes it, and an empty one clears it', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.files.select('/workspaces/q3/PROMPT.md');
      expect(await rig.files.save('Answer in French.'), isTrue);
      expect(llm.spaces.first.prompt, 'Answer in French.');
      expect(rig.files.text, 'Answer in French.');
      await rig.files.save('  \n');
      expect(llm.spaces.first.prompt, isNull);
    });

    test('settings write only what changed', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.files.select('/workspaces/q3/settings.json');
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
      await rig.files.select('/workspaces/q3/settings.json');
      final draft = rig.files.text!.replaceFirst('"automatic"', '"query"');
      llm.calls.clear();
      expect(await rig.files.save(draft), isFalse);
      expect(llm.calls, isNot(contains('updateWorkspace:q3')));
      expect(rig.files.problems.single.text, contains('chatMode'));
    });
  });

  group('documents', () {
    test(
      'detaching takes a document out of the workspace and refreshes Sources',
      () async {
        final llm = planningServer();
        final rig = await started(llm);
        await rig.files.select('/workspaces/q3/docs/$roadmap');
        await rig.files.detach('q3', roadmap);
        expect(
          llm.spaces.first.docs.map((d) => d.path),
          isNot(contains(roadmap)),
        );
        expect(llm.library, contains(roadmap));
        expect(rig.files.selected, '/workspaces/q3/docs');
        await pumpEventQueue();
        expect(rig.sources.files.map((f) => f.path), isNot(contains(roadmap)));
      },
    );

    test(
      'attaching an inactive workspace\'s document updates its count',
      () async {
        final llm = planningServer();
        final rig = await started(llm);
        await rig.files.attach('household', roadmap);
        expect(llm.spaces.last.docs.single.path, roadmap);
        expect(rig.chat.docCounts['household'], 1);
      },
    );

    test('pinning marks the link', () async {
      final rig = await started(planningServer());
      await rig.files.pin('q3', roadmap, pinned: true);
      expect(rig.files.docIn('q3', roadmap)!.pinned, isTrue);
    });

    test(
      'uploading files them in the folder, and a wrong type says why',
      () async {
        final llm = planningServer();
        final rig = await started(llm);
        await rig.files.upload('notes', [
          UploadFile(name: 'a.md', read: () async => [1]),
          UploadFile(name: 'b.exe', read: () async => [1]),
        ]);
        expect(llm.calls, contains('upload:notes/a.md'));
        expect(nodeAt(rig.files.tree, '/library/notes/a.md.json'), isNotNull);
        expect(rig.files.problems.single.title, 'Could not add b.exe');
      },
    );

    test('a new folder shows while empty', () async {
      final rig = await started(planningServer());
      await rig.files.createFolder(' notes ');
      expect(nodeAt(rig.files.tree, '/library/notes'), isNotNull);
      expect(rig.files.expanded, contains('/library/notes'));
    });

    test('moving a free document selects it in its new folder', () async {
      final llm = planningServer();
      final free = libraryDoc(llm, 'loose.md');
      await llm.createFolder('archive');
      final rig = await started(llm);
      await rig.files.move(free.path, 'archive');
      expect(llm.library, contains('archive/loose.md.json'));
      expect(rig.files.selected, '/library/archive/loose.md.json');
    });

    test(
      'moving a document a workspace uses says the server kept it',
      () async {
        final llm = planningServer();
        await llm.createFolder('archive');
        final rig = await started(llm);
        await rig.files.move(roadmap, 'archive');
        expect(llm.library, contains(roadmap));
        expect(
          rig.files.problems.single.title,
          'The server kept the document where it was',
        );
      },
    );

    test('deleting from the library leaves every workspace and the switched-off list', () async {
      final llm = planningServer();
      final rig = await started(
        llm,
        prefs: const Prefs(
          switchedOff: {
            'household': [OffDoc(path: roadmap, title: 'Q3 roadmap.pdf')],
          },
        ),
      );
      await rig.files.select('/library/$roadmap');
      await rig.files.deleteFromLibrary(roadmap);
      expect(llm.calls, contains('removeDocuments:$roadmap'));
      expect(
        llm.spaces.first.docs.map((d) => d.path),
        isNot(contains(roadmap)),
      );
      expect(rig.prefs.prefs.offIn('household'), isEmpty);
      expect(rig.files.selected, '/library/custom-documents');
      expect(nodeAt(rig.files.tree, '/workspaces/q3/docs/$roadmap'), isNull);
    });
  });

  test(
    'deleting a folder takes its files out of the library and the workspaces',
    () async {
      final llm = planningServer();
      final rig = await started(
        llm,
        prefs: const Prefs(
          switchedOff: {
            'household': [OffDoc(path: roadmap, title: 'Q3 roadmap.pdf')],
          },
        ),
      );
      await rig.files.select('/library/$roadmap');
      await rig.files.deleteFolder('custom-documents');
      expect(llm.calls, contains('removeFolder:custom-documents'));
      expect(llm.spaces.first.docs, isEmpty);
      expect(rig.prefs.prefs.offIn('household'), isEmpty);
      expect(rig.files.selected, '/library');
      expect(nodeAt(rig.files.tree, '/library/custom-documents'), isNull);
      expect(nodeAt(rig.files.tree, '/workspaces/q3/docs/$roadmap'), isNull);
    },
  );

  test('a refused folder delete says why and keeps the folder', () async {
    final llm = planningServer()
      ..errors['removeFolder'] = const ApiException('Folder in use');
    final rig = await started(llm);
    await rig.files.deleteFolder('custom-documents');
    expect(rig.files.problems.single.text, 'Folder in use');
    expect(nodeAt(rig.files.tree, '/library/custom-documents'), isNotNull);
  });

  test('a deleted workspace leaves the tree and the users of a file', () async {
    final rig = await started(planningServer());
    await rig.files.select('/workspaces/q3/PROMPT.md');
    expect(rig.files.usersOf(roadmap).map((w) => w.slug), ['q3']);
    await rig.chat.deleteWorkspace('q3');
    await pumpEventQueue();
    expect(rig.files.usersOf(roadmap), isEmpty);
    expect(nodeAt(rig.files.tree, '/workspaces/q3'), isNull);
    expect(rig.files.selected, '/workspaces');
  });

  test('a new server starts afresh', () async {
    final rig = await started(planningServer());
    await rig.files.select('/workspaces/q3/PROMPT.md');
    await rig.settings.save('https://other:3001', 'K2');
    await pumpEventQueue();
    expect(rig.files.selected, isNull);
    expect(nodeAt(rig.files.tree, '/workspaces/q3/PROMPT.md'), isNull);
  });

  test('a workspace made after loading is read too', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await rig.chat.createWorkspace('Travel');
    await pumpEventQueue();
    expect(nodeAt(rig.files.tree, '/workspaces/travel/PROMPT.md'), isNotNull);
  });
}
