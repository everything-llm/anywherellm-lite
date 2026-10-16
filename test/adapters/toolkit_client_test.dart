import 'dart:convert';

import 'package:anywherellm/adapters/toolkit_client.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_toolkit.dart';

const _connection = Connection(
  baseUrl: 'https://host.example.ts.net:3001',
  apiKey: 'SECRET-KEY',
);

const _health = {
  'ok': true,
  'service': 'anythingllm-bridge',
  'allow': ['GET /memories', 'not a rule'],
};

/// A toolkit that answers each path with its JSON in [routes], recording each request.
class _Toolkit {
  final routes = <String, Object?>{'/health': _health};
  final seen = <http.Request>[];

  HttpToolkitApi api([Connection connection = _connection]) => HttpToolkitApi(
    holder: ConnectionHolder(connection),
    client: MockClient((request) async {
      seen.add(request);
      final body = routes[request.url.path];
      if (body is http.Response) return body;
      return body == null
          ? http.Response('', 404)
          : http.Response(jsonEncode(body), 200);
    }),
  );
}

Future<ApiException> _failure(Future<void> call) async {
  try {
    await call;
  } on ApiException catch (error) {
    return error;
  }
  fail('expected an ApiException');
}

void main() {
  test(
    'its features are what the routes its bridge allows let through',
    () async {
      final toolkit = _Toolkit();
      // Reading memories alone is not enough to show them: the page changes them too.
      expect(await toolkit.api().features(), isEmpty);
      expect(toolkit.seen.single.url.port, 8467);
      toolkit.routes['/health'] = {
        ..._health,
        'allow': liteBridgeAllow.split(', '),
      };
      expect(await toolkit.api().features(), {
        ToolkitFeature.memories,
        ToolkitFeature.jobs,
        ToolkitFeature.jobsWrite,
      });
      toolkit.routes['/health'] = {'service': 'other'};
      expect(await toolkit.api().features(), isNull);
    },
  );

  group('scheduled jobs', () {
    const draft = JobDraft(
      name: 'Brief',
      prompt: 'Summarise today.',
      cron: '0 7 * * *',
    );

    test('a job\'s runs are listed, newest first', () async {
      final toolkit = _Toolkit()
        ..routes['/scheduled-jobs/7/runs'] = {
          'runs': [
            {'status': 'running'},
            {'status': 'failed', 'error': 'The site answered 503'},
            {'status': 'completed'},
          ],
        };
      final runs = await toolkit.api().jobRuns('7', limit: 2);
      expect(runs.map((r) => r.status), ['running', 'failed']);
    });

    test('a job is made, changed, switched, run and deleted', () async {
      final toolkit = _Toolkit()
        ..routes['/scheduled-jobs/new'] = {
          'job': {'id': 7},
          'error': null,
        }
        ..routes['/scheduled-jobs/7'] = {'success': true}
        ..routes['/scheduled-jobs/7/trigger'] = {
          'success': true,
          'skipped': false,
          'error': null,
        };
      final api = toolkit.api();

      await api.createJob(draft);
      expect(toolkit.seen.last.method, 'POST');
      expect(toolkit.seen.last.url.path, '/scheduled-jobs/new');
      expect(jsonDecode(toolkit.seen.last.body), draft.toJson());

      await api.updateJob('7', draft);
      expect(toolkit.seen.last.method, 'PUT');
      expect(toolkit.seen.last.url.path, '/scheduled-jobs/7');

      await api.setJobEnabled('7', false);
      expect(jsonDecode(toolkit.seen.last.body), {'enabled': false});

      await api.runJob('7');
      expect(toolkit.seen.last.method, 'POST');
      expect(toolkit.seen.last.url.path, '/scheduled-jobs/7/trigger');

      await api.deleteJob('7');
      expect(toolkit.seen.last.method, 'DELETE');
      for (final request in toolkit.seen.skip(1)) {
        expect(request.headers['Authorization'], 'Bearer SECRET-KEY');
      }
    });

    test('a run AnythingLLM skips, or a delete it misses, fails', () async {
      final toolkit = _Toolkit()
        ..routes['/scheduled-jobs/7'] = {'success': false}
        ..routes['/scheduled-jobs/7/trigger'] = {
          'success': true,
          'skipped': true,
        };
      final api = toolkit.api();
      expect((await _failure(api.runJob('7'))).message, contains('running'));
      expect((await _failure(api.deleteJob('7'))).message, contains('gone'));
    });

    test('a refusal fails in AnythingLLM\'s words, without the key', () async {
      final toolkit = _Toolkit()
        ..routes['/scheduled-jobs/new'] = http.Response(
          jsonEncode({'job': null, 'error': 'Invalid cron expression'}),
          400,
        );
      final failure = await _failure(toolkit.api().createJob(draft));
      expect(failure.message, 'Invalid cron expression.');
      expect(failure.status, 400);
      expect(failure.message, isNot(contains('SECRET-KEY')));
    });

    test(
      'a refusal AnythingLLM answers with HTTP 200 fails all the same',
      () async {
        final toolkit = _Toolkit()
          ..routes['/admin/system-preferences'] = {
            'success': false,
            'error': 'Not allowed.',
          }
          ..routes['/scheduled-jobs/7'] = {'success': false};
        final api = toolkit.api();
        expect(
          (await _failure(api.setMemorySwitches(enabled: true))).message,
          'Not allowed.',
        );
        expect(
          (await _failure(api.setJobEnabled('7', true))).message,
          'AnythingLLM did not do it.',
        );
      },
    );

    test('a route the bridge does not pass fails in its words', () async {
      final toolkit = _Toolkit()
        ..routes['/scheduled-jobs'] = http.Response(
          jsonEncode({'error': "the bridge doesn't pass GET /scheduled-jobs"}),
          403,
        );
      final failure = await _failure(toolkit.api().scheduledJobs());
      expect(failure.status, 403);
      expect(failure.message, contains("bridge doesn't pass"));
    });
  });

  group('the Library and the Activity', () {
    test('the Library is read whole, and an activity by pages', () async {
      final toolkit = _Toolkit()
        ..routes['/library'] = {
          'apps': [
            {'title': 'Groceries', 'page': '/apps-lean/g1.html'},
          ],
          'files': [
            {'storageFilename': 'pdf-1.pdf', 'name': 'Quote.pdf'},
          ],
        }
        ..routes['/activity'] = {
          'events': [
            {
              'id': 'e2',
              'at': '2026-10-14T16:00:00Z',
              'title': 'Price watch',
              'kind': 'action',
              'outcome': 'failed',
            },
          ],
          'more': true,
        };
      final api = toolkit.api();
      final library = await api.library();
      expect(library.apps.single.title, 'Groceries');
      expect(library.files.single.file.name, 'Quote.pdf');
      expect(toolkit.seen.last.url.path, '/library');
      expect(toolkit.seen.last.headers['Authorization'], 'Bearer SECRET-KEY');

      final first = await api.activity();
      expect(first.events.single.title, 'Price watch');
      expect(first.more, isTrue);
      expect(toolkit.seen.last.url.queryParameters, {'limit': '50'});
      await api.activity(before: 'e2', limit: 10);
      expect(toolkit.seen.last.url.queryParameters, {
        'limit': '10',
        'before': 'e2',
      });
    });
  });

  group('saved memories', () {
    test('the switches are read and written', () async {
      final toolkit = _Toolkit()
        ..routes['/admin/system-preferences-for'] = {
          'settings': {
            'memory_enabled': 'true',
            'memory_auto_extraction': 'false',
          },
        }
        ..routes['/admin/system-preferences'] = {'success': true};
      final api = toolkit.api();
      final switches = await api.memorySwitches();
      expect((switches.enabled, switches.learn), (true, false));
      expect(toolkit.seen.last.url.queryParameters, {
        'labels': 'memory_enabled,memory_auto_extraction',
      });
      await api.setMemorySwitches(learn: true);
      expect(toolkit.seen.last.method, 'POST');
      expect(jsonDecode(toolkit.seen.last.body), {
        'memory_auto_extraction': 'true',
      });
      expect(toolkit.seen.last.headers['Authorization'], 'Bearer SECRET-KEY');
    });

    test(
      'a workspace\'s memories are listed, added, edited and moved',
      () async {
        final memory = {
          'id': 7,
          'content': 'Prefers metric units.',
          'scope': 'global',
        };
        final toolkit = _Toolkit()
          ..routes['/workspaces/q3/memories'] = {
            'memories': {
              'global': [memory],
              'workspace': [
                {
                  'id': 8,
                  'content': 'Reports go to Maja.',
                  'scope': 'workspace',
                },
                {'id': 'bad'},
              ],
            },
            'memory': memory,
          }
          ..routes['/memories/7'] = {'memory': memory}
          ..routes['/memories/7/demote/q3'] = {
            'memory': {...memory, 'scope': 'workspace'},
          }
          ..routes['/memories/7/promote'] = {'memory': memory};
        final api = toolkit.api();
        final listed = await api.savedMemories('q3');
        expect(
          [for (final m in listed.global) m.text],
          ['Prefers metric units.'],
        );
        expect([for (final m in listed.workspace) m.id], [8]);

        final added = await api.addMemory(
          'q3',
          'Prefers metric units.',
          global: true,
        );
        expect(added.id, 7);
        expect(toolkit.seen.last.method, 'POST');
        expect(jsonDecode(toolkit.seen.last.body), {
          'content': 'Prefers metric units.',
          'scope': 'global',
        });

        await api.editMemory(7, 'Prefers metric.');
        expect(toolkit.seen.last.method, 'PUT');
        expect(jsonDecode(toolkit.seen.last.body), {
          'content': 'Prefers metric.',
        });

        final moved = await api.moveMemory(7, toWorkspace: 'q3');
        expect(moved.global, isFalse);
        expect(toolkit.seen.last.url.path, '/memories/7/demote/q3');
        final back = await api.moveMemory(7);
        expect(back.global, isTrue);
        expect(toolkit.seen.last.url.path, '/memories/7/promote');

        await api.deleteMemory(7);
        expect(toolkit.seen.last.method, 'DELETE');
        expect(toolkit.seen.last.url.path, '/memories/7');
      },
    );

    test('a refusal fails in AnythingLLM\'s words, without the key', () async {
      final toolkit = _Toolkit()
        ..routes['/workspaces/q3/memories'] = http.Response(
          jsonEncode({'error': 'Maximum global memory limit (5) reached.'}),
          400,
        );
      final error = await _failure(
        toolkit.api().addMemory('q3', 'One more.', global: true),
      );
      expect(
        error.message,
        contains('Maximum global memory limit (5) reached.'),
      );
      expect(error.status, 400);
      expect(error.message, isNot(contains('SECRET-KEY')));
    });
  });

  test('the scheduled jobs are read', () async {
    final toolkit = _Toolkit()
      ..routes['/scheduled-jobs'] = {
        'jobs': [
          {
            'id': 1,
            'name': 'Morning brief',
            'schedule': '0 7 * * *',
            'enabled': true,
            'nextRunAt': '2026-10-09T07:00:00Z',
            'lastRunAt': null,
            'latestRun': {'status': 'completed'},
          },
        ],
      };
    final jobs = await toolkit.api().scheduledJobs();
    expect(jobs.single.name, 'Morning brief');
    expect(jobs.single.nextRun, DateTime.utc(2026, 10, 9, 7));
  });
}
