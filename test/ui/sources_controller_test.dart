import 'dart:async';

import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/core/upload.dart';
import 'package:anywherellm/ui/state/sources_controller.dart';
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

class _SlowSettingsStore extends FakeSettingsStore {
  final gate = Completer<void>();

  @override
  Future<void> save(Connection connection) async {
    await gate.future;
    await super.save(connection);
  }
}

void main() {
  test(
    'an upload stops before the new keyring entry finishes saving',
    () async {
      final llm = planningServer();
      final store = _SlowSettingsStore();
      final rig = Rig(llm: llm, store: store, connection: sampleConnection);
      addTearDown(rig.dispose);
      await rig.start();
      final bytes = Completer<List<int>>();
      final uploading = rig.sources.upload([
        UploadFile(name: 'private.md', read: () => bytes.future),
      ]);
      await pumpEventQueue();
      final saving = rig.settings.save('https://other:3001', 'K2');
      bytes.complete([1]);
      await uploading;
      expect(llm.calls, isNot(contains('upload:private.md')));
      store.gate.complete();
      await saving;
      await pumpEventQueue();
    },
  );

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

  test('a late removal offers no undo in another workspace', () async {
    final llm = planningServer();
    final rig = await started(llm);
    final gate = llm.gates['updateEmbeddings'] = Completer<void>();
    final removing = rig.sources.remove(rig.sources.files.first);
    await rig.chat.select('household');
    gate.complete();
    await removing;
    expect(rig.sources.removed, isNull);
    await rig.sources.undo();
    expect(llm.spaces.last.docs, isEmpty);
    expect(llm.spaces.first.docs, hasLength(1));
  });

  test(
    'a server switch stops an upload before the next file or embedding',
    () async {
      final llm = planningServer();
      final rig = await started(llm);
      final gate = llm.gates['upload'] = Completer<void>();
      final uploading = rig.sources.upload([file('a.md'), file('b.md')]);
      await pumpEventQueue();
      await rig.settings.save('https://other:3001', 'K2');
      await pumpEventQueue();
      gate.complete();
      await uploading;
      expect(llm.calls, contains('upload:a.md'));
      expect(llm.calls, isNot(contains('upload:b.md')));
      expect(
        llm.calls.where((call) => call.startsWith('updateEmbeddings')),
        isEmpty,
      );
      expect(rig.sources.sending, isNull);
    },
  );

  test(
    'renaming an unordered workspace keeps its switched-off sources',
    () async {
      final llm = planningServer()..renamedSlug = 'q4';
      final rig = await started(llm);
      await rig.sources.toggle(rig.sources.files.first);
      await rig.chat.renameWorkspace('q3', 'Q4');
      await pumpEventQueue();
      expect(rig.prefs.prefs.offIn('q3'), isEmpty);
      expect(rig.prefs.prefs.offIn('q4'), hasLength(1));
      expect(rig.sources.files.where((file) => !file.on), hasLength(1));
      await rig.sources.toggle(rig.sources.files.last);
      expect(llm.spaces.first.docs, hasLength(2));
    },
  );

  test('a refresh cut short by forgetting the server stops loading', () async {
    final llm = planningServer();
    final rig = await started(llm);
    final gate = llm.gates['workspace'] = Completer<void>();
    final refreshing = rig.sources.refresh();
    expect(rig.sources.loading, isTrue);
    await rig.settings.clear();
    gate.complete();
    await refreshing;
    expect(rig.sources.loading, isFalse);
  });

  test(
    'an upload that ends in another workspace leaves its notices out',
    () async {
      final llm = planningServer()
        ..errors['upload'] = const ApiException('nope');
      final rig = await started(llm);
      final gate = llm.gates['upload'] = Completer<void>();
      final uploading = rig.sources.upload([file('a.md')]);
      await pumpEventQueue();
      expect(rig.sources.sending, 'a.md');
      await rig.chat.select('household');
      gate.complete();
      await uploading;
      expect(rig.sources.problems, isEmpty);
      expect(rig.sources.sending, isNull);
    },
  );

  test('a new server is asked which files it reads', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await rig.sources.upload([file('a.md')]);
    await rig.settings.save('https://other:3001', 'K2');
    await pumpEventQueue();
    await rig.sources.upload([file('b.md')]);
    expect(llm.calls.where((c) => c == 'acceptedExtensions'), hasLength(2));
  });

  group('links and text', () {
    test('a link is read in and embedded', () async {
      final llm = planningServer();
      final rig = await started(llm);
      expect(rig.sources.addLink(' https://example.com/page '), isTrue);
      await pumpEventQueue();
      expect(
        llm.calls,
        containsAllInOrder([
          'uploadLink:https://example.com/page',
          'updateEmbeddings:+custom-documents/url-example.com.json-',
        ]),
      );
      expect(rig.sources.files.last.title, 'example.com');
      expect(rig.sources.sending, isNull);
      expect(rig.sources.problems, isEmpty);
    });

    test('pasted text is saved under its title and embedded', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.sources.addText('Meeting notes', 'We agreed on 40k.');
      expect(
        llm.calls,
        containsAllInOrder([
          'uploadText:Meeting notes',
          'updateEmbeddings:+custom-documents/raw-Meeting notes.json-',
        ]),
      );
      expect(rig.sources.files.last.title, 'Meeting notes');
    });

    test('the details of a link, text and a file reach the server', () async {
      final llm = planningServer();
      final rig = await started(llm);
      const meta = DocMeta(author: 'Ada', source: 'Finance');
      rig.sources.addLink('https://example.com/page', meta: meta);
      await pumpEventQueue();
      await rig.sources.addText('Notes', 'Some text', meta: meta);
      await rig.sources.upload([
        UploadFile(
          name: 'a.md',
          read: () async => [1],
          meta: const DocMeta(title: 'Plan'),
        ),
      ]);
      expect(
        llm.metaOf['custom-documents/url-example.com.json']?.author,
        'Ada',
      );
      expect(llm.metaOf['custom-documents/raw-Notes.json']?.source, 'Finance');
      expect(llm.metaOf['custom-documents/a.md.json']?.title, 'Plan');
      expect(rig.sources.files.map((f) => f.title), contains('Plan'));
    });

    test('an address that is not a link never reaches the server', () async {
      final llm = planningServer();
      final rig = await started(llm);
      expect(rig.sources.addLink('example.com'), isFalse);
      expect(llm.calls.where((c) => c.startsWith('uploadLink')), isEmpty);
      expect(rig.sources.problems.single.text, contains('https://'));
    });

    test('a refused link becomes a notice', () async {
      final llm = planningServer()
        ..errors['uploadLink'] = const ApiException('The page did not load.');
      final rig = await started(llm);
      rig.sources.addLink('https://example.com');
      await pumpEventQueue();
      expect(
        rig.sources.problems.single.title,
        'Could not add https://example.com',
      );
      expect(rig.sources.problems.single.text, 'The page did not load.');
      expect(rig.sources.sending, isNull);
      expect(llm.calls.where((c) => c.startsWith('updateEmbeddings')), isEmpty);
    });
  });

  group('testing a question', () {
    test('finds passages of the workspace\'s files, closest first', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.sources.search(' roadmap ');
      expect(llm.calls, contains('searchDocs:q3:roadmap'));
      expect(rig.sources.searched, 'roadmap');
      expect(rig.sources.hits?.map((h) => h.title), ['Q3 roadmap.pdf']);
      expect(rig.sources.searching, isFalse);
    });

    test('a blank question is not sent', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.sources.search('  ');
      expect(llm.calls.where((c) => c.startsWith('searchDocs')), isEmpty);
      expect(rig.sources.hits, isNull);
    });

    test('a refused question becomes a notice', () async {
      final llm = planningServer()
        ..errors['searchDocs'] = const ApiException('No vectors');
      final rig = await started(llm);
      await rig.sources.search('roadmap');
      expect(rig.sources.problems.single.text, 'No vectors');
      expect(rig.sources.hits, isNull);
    });

    test('another workspace puts the question away', () async {
      final rig = await started(planningServer());
      await rig.sources.search('roadmap');
      await rig.chat.select('household');
      expect(rig.sources.searched, isNull);
      expect(rig.sources.hits, isNull);
    });

    test('an answer for an older question is dropped', () async {
      final llm = planningServer();
      final rig = await started(llm);
      final gate = llm.gates['searchDocs'] = Completer<void>();
      final first = rig.sources.search('roadmap');
      await pumpEventQueue();
      rig.sources.clearSearch();
      gate.complete();
      await first;
      expect(rig.sources.hits, isNull);
    });
  });

  group('chat mode', () {
    test('is read with the workspace and changed on the server', () async {
      final llm = planningServer();
      final rig = await started(llm);
      expect(rig.sources.chatMode.value, ChatMode.automatic);
      await rig.sources.setChatMode(ChatMode.query);
      expect(llm.calls, contains('updateWorkspace:q3'));
      expect(llm.spaces.first.settings['chatMode'], 'query');
      expect(rig.sources.chatMode.value, ChatMode.query);
    });

    test('a refused change goes back and says why', () async {
      final llm = planningServer()
        ..errors['updateWorkspace'] = const ApiException('No');
      final rig = await started(llm);
      await rig.sources.setChatMode(ChatMode.chat);
      expect(rig.sources.chatMode.value, ChatMode.automatic);
      expect(
        rig.sources.problems.single.title,
        'Could not change the chat mode',
      );
    });

    test('another workspace shows its own mode', () async {
      final llm = planningServer();
      llm.spaces.last.settings['chatMode'] = 'chat';
      final rig = await started(llm);
      await rig.chat.select('household');
      await pumpEventQueue();
      expect(rig.sources.chatMode.value, ChatMode.chat);
    });
  });
}
