// The app's own adapters against a real AnythingLLM and anywherellm-bridge, which the bridge's
// `tools/e2e` starts and `tool/e2e/e2e.py inside` points at the model stub:
//
//   flutter test tool/e2e/contract.dart
//
// It reads E2E_ALLM_URL, E2E_KEY, E2E_BRIDGE_URL and E2E_WORKSPACE, and E2E_PAGE, a page the
// server's collector can read, and skips every check without them. It sits outside `test/`, so
// `flutter test` alone does not run it. Each check is a plain `test`: a `testWidgets` binding
// answers every HTTP request with 400. The checks run in order on one server, and each leaves it
// as later ones expect.
import 'dart:io';

import 'package:anywherellm/adapters/anythingllm_client.dart';
import 'package:anywherellm/adapters/toolkit_client.dart';
import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/core/system_settings.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:flutter_test/flutter_test.dart';

final _env = Platform.environment;
final _skip = _env['E2E_ALLM_URL'] == null
    ? 'run it through tool/e2e/e2e.py'
    : null;

/// The question the chat checks ask, and what the stub answers to it.
const question = 'When does the harbour open?';
const answer = 'E2E answer to: $question';

void main() {
  late Connection connection;
  late AnythingLlmApi llm;
  late ToolkitApi toolkit;
  late String slug;

  setUpAll(() {
    if (_skip != null) return;
    connection = Connection.parse(_env['E2E_ALLM_URL']!, _env['E2E_KEY']!);
    final holder = ConnectionHolder(
      connection,
    )..companions = {toolkitCompanion.code: Uri.parse(_env['E2E_BRIDGE_URL']!)};
    llm = HttpAnythingLlmApi(holder: holder);
    toolkit = HttpToolkitApi(holder: holder);
    slug = _env['E2E_WORKSPACE']!;
  });

  group('AnythingLLM', skip: _skip, () {
    test('the key opens the server', () => llm.verify(connection));

    test('the list names the workspace, and its detail has settings and no documents', () async {
      final listed = await llm.workspaces();
      expect(listed.map((w) => w.slug), contains(slug));
      final one = await llm.workspace(slug);
      expect(one.name, 'E2E Workspace');
      expect(one.documents, isEmpty);
      expect(one.settings?.values['chatMode'], 'chat');
    });

    test('a rename keeps the slug', () async {
      final renamed = await llm.renameWorkspace(slug, 'E2E Renamed');
      expect(renamed.slug, slug);
      expect(renamed.name, 'E2E Renamed');
      await llm.renameWorkspace(slug, 'E2E Workspace');
    });

    test('a workspace made and deleted leaves the list', () async {
      final made = await llm.createWorkspace(
        'E2E Scratch',
        prompt: 'Be brief.',
      );
      expect((await llm.workspace(made.slug)).prompt, 'Be brief.');
      await llm.deleteWorkspace(made.slug);
      expect(
        (await llm.workspaces()).map((w) => w.slug),
        isNot(contains(made.slug)),
      );
    });

    late String thread;
    late int chatId;

    test('a chat is named in the list call', () async {
      thread = (await llm.createThread(slug)).slug;
      await llm.renameThread(slug, thread, 'Contract chat');
      final listed = (await llm.workspaces()).firstWhere((w) => w.slug == slug);
      expect(
        listed.threads.map((t) => (t.slug, t.name)),
        contains((thread, 'Contract chat')),
      );
    });

    test(
      'an answer streams the model text and closes with its chatId and metrics',
      () async {
        final events = await llm.streamChat(slug, thread, question).toList();
        final text = events.whereType<TextChunk>().map((e) => e.text).join();
        expect(text, answer);
        final done = events.last;
        expect(done, isA<ChatDone>());
        done as ChatDone;
        expect(done.chatId, isNotNull);
        expect(done.metrics?.model, 'e2e-model');
        chatId = done.chatId!;
      },
    );

    test('the history lists the exchange under that chatId', () async {
      final turns = await llm.history(slug, thread);
      expect(turns.map((t) => t.text), [question, answer]);
      expect(turns.map((t) => t.chatId), [chatId, chatId]);
      expect(turns.last.metrics?.model, 'e2e-model');
    });

    test('a reset empties the history', () async {
      await llm.resetChat(slug, thread);
      expect(await llm.history(slug, thread), isEmpty);
    });

    test('a deleted chat leaves the list', () async {
      await llm.deleteThread(slug, thread);
      final listed = (await llm.workspaces()).firstWhere((w) => w.slug == slug);
      expect(listed.threads.map((t) => t.slug), isNot(contains(thread)));
    });

    test('the server reads text and pdf files', () async {
      expect(
        await llm.acceptedExtensions(),
        containsAll(['.txt', '.md', '.pdf']),
      );
    });

    late String notes;

    test(
      'pasted text is stored under a file name, embedded, found and dropped',
      () async {
        final made = await llm.uploadText(
          'Harbour notes',
          'The harbour opens at dawn and closes at dusk.',
          meta: const DocMeta(author: 'E2E', description: 'Opening hours'),
        );
        expect(made, hasLength(1));
        notes = made.single.path;
        expect((await llm.document(notes)).title, startsWith('harbour-notes'));
        await llm.updateEmbeddings(slug, adds: [notes]);
        final docs = (await llm.workspace(slug)).documents;
        expect(docs.map((d) => d.path), contains(notes));
        expect(docs.firstWhere((d) => d.path == notes).web, isFalse);

        final hits = await llm.searchDocs(slug, question);
        expect(hits, isNotEmpty);
        expect(hits.first.text, contains('harbour'));
        expect(hits.first.score, inInclusiveRange(0, 1));
        expect(await llm.vectorCount(), greaterThan(0));

        await llm.updateEmbeddings(slug, deletes: [notes]);
        expect(
          (await llm.workspace(slug)).documents.map((d) => d.path),
          isNot(contains(notes)),
        );
      },
    );

    test('a web page is read in as a link', () async {
      final made = await llm.uploadLink(_env['E2E_PAGE']!);
      expect(made, isNotEmpty);
      await llm.updateEmbeddings(slug, adds: [made.first.path]);
      final docs = (await llm.workspace(slug)).documents;
      expect(docs.firstWhere((d) => d.path == made.first.path).web, isTrue);
      await llm.updateEmbeddings(slug, deletes: [made.first.path]);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('the settings name the stub model and hide its key', () async {
      final settings = await llm.systemSettings();
      expect(systemChatModel(settings), (
        provider: 'generic-openai',
        model: 'e2e-model',
      ));
      expect(settings['GenericOpenAiKey'], isTrue);
    });

    test('telemetry is the one setting the app writes', () async {
      await llm.updateSystem({'DisableTelemetry': 'true'});
      expect(
        settingText(await llm.systemSettings(), 'DisableTelemetry'),
        'true',
      );
    });

    test('a refused setting fails the write', () async {
      await expectLater(
        llm.updateSystem({'VectorDB': 'no-such-db'}),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('the bridge', skip: _skip, () {
    test('serves memories and jobs under the default allow list', () async {
      final features = await toolkit.features(again: true);
      expect(
        features,
        containsAll([
          ToolkitFeature.memories,
          ToolkitFeature.jobs,
          ToolkitFeature.jobsWrite,
        ]),
      );
    });

    test('saved memories: on, add, move, edit, the limit, delete', () async {
      await toolkit.setMemorySwitches(enabled: true, learn: false);
      final switches = await toolkit.memorySwitches();
      expect((switches.enabled, switches.learn), (true, false));

      final mine = await toolkit.addMemory(
        slug,
        'The user likes tea.',
        global: false,
      );
      expect(mine.global, isFalse);
      final everywhere = await toolkit.moveMemory(mine.id);
      expect(everywhere.global, isTrue);
      final back = await toolkit.moveMemory(mine.id, toWorkspace: slug);
      expect(back.global, isFalse);
      expect(
        (await toolkit.editMemory(mine.id, 'The user likes green tea.')).text,
        'The user likes green tea.',
      );

      final globals = [
        for (var i = 0; i < 5; i++)
          await toolkit.addMemory(slug, 'Fact $i.', global: true),
      ];
      await expectLater(
        toolkit.addMemory(slug, 'One too many.', global: true),
        throwsA(isA<ApiException>()),
      );
      final saved = await toolkit.savedMemories(slug);
      expect((saved.global.length, saved.workspace.length), (5, 1));

      for (final m in [mine, ...globals]) {
        await toolkit.deleteMemory(m.id);
      }
      final left = await toolkit.savedMemories(slug);
      expect([...left.global, ...left.workspace], isEmpty);
    });

    test('memories switched off are refused', () async {
      await toolkit.setMemorySwitches(enabled: false);
      await expectLater(
        toolkit.savedMemories(slug),
        throwsA(isA<ApiException>()),
      );
      await toolkit.setMemorySwitches(enabled: true);
    });

    test('a scheduled job: made, listed, changed, run and deleted', () async {
      await toolkit.createJob(
        const JobDraft(
          name: 'E2E job',
          prompt: 'Say hello.',
          cron: '0 6 * * *',
        ),
      );
      var job = (await toolkit.scheduledJobs()).firstWhere(
        (j) => j.name == 'E2E job',
      );
      expect((job.cron, job.enabled), ('0 6 * * *', true));
      final id = job.id!;

      await toolkit.updateJob(
        id,
        const JobDraft(name: 'E2E job', prompt: 'Say hi.', cron: '30 7 * * 1'),
      );
      await toolkit.setJobEnabled(id, false);
      job = (await toolkit.scheduledJobs()).firstWhere((j) => j.id == id);
      expect(
        (job.prompt, job.cron, job.enabled),
        ('Say hi.', '30 7 * * 1', false),
      );

      await toolkit.runJob(id);
      var runs = <JobRun>[];
      for (var i = 0; i < 20 && runs.isEmpty; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        runs = await toolkit.jobRuns(id);
      }
      expect(runs, isNotEmpty);

      await toolkit.deleteJob(id);
      expect(
        (await toolkit.scheduledJobs()).map((j) => j.id),
        isNot(contains(id)),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a cron that is not five fields is refused', () async {
      await expectLater(
        toolkit.createJob(
          const JobDraft(name: 'Bad', prompt: 'x', cron: 'every day'),
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
