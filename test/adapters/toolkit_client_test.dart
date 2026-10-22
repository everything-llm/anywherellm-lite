import 'dart:convert';
import 'dart:io';

import 'package:anywherellm/adapters/toolkit_client.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/core/skill_pages.dart';
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
    holder: pairedHolder(
      connection,
      Uri.parse('https://host.example.ts.net:8467'),
    ),
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

/// The toolkit, at the address a pairing code said beside [holder]'s connection, answering
/// through [handler].
HttpToolkitApi _api(
  Future<http.Response> Function(http.Request) handler, {
  ConnectionHolder? holder,
}) => HttpToolkitApi(
  holder:
      holder ??
      pairedHolder(_connection, Uri.parse('https://host.example.ts.net:8467')),
  client: MockClient(handler),
);

/// A toolkit that answers [body] to every request and records each one in [seen].
HttpToolkitApi _answering(
  Object body, {
  List<http.Request>? seen,
  int status = 200,
}) => _api((request) async {
  seen?.add(request);
  return http.Response(jsonEncode(body), status);
});

Future<ApiException> _failure(Future<void> call) async {
  try {
    await call;
  } on ApiException catch (error) {
    return error;
  }
  fail('expected an ApiException');
}

void main() {
  group('health', () {
    test('asks /health where it was said to run without the key, and believes '
        'only the toolkit server', () async {
      final seen = <http.Request>[];
      final api = _answering({
        'service': 'anywherellm-bridge',
        'server': 'toolkit',
        'ok': true,
      }, seen: seen);
      expect(await api.features(), isNotNull);
      expect(
        seen.single.url.toString(),
        'https://host.example.ts.net:8467/health',
      );
      expect(seen.single.headers.containsKey('Authorization'), isFalse);
    });

    test(
      'believes the toolkit by its names before the rename and the suite',
      () async {
        for (final name in ['anythingllm-bridge', 'anythingllm-toolkit']) {
          expect(await _answering({'service': name}).features(), isNotNull);
        }
      },
    );

    test('is null for anything else that answers, or nothing', () async {
      expect(await _answering({'service': 'other'}).features(), isNull);
      expect(
        await _api((_) async => http.Response('<html>AnythingLLM</html>', 200))
            .features(),
        isNull,
      );
      expect(
        await _answering({
          'service': 'anythingllm-bridge',
        }, status: 502).features(),
        isNull,
      );
      expect(
        await _api((_) async => throw const SocketException('refused'))
            .features(),
        isNull,
      );
    });

    test('is remembered per address, until asked again', () async {
      var asked = 0;
      final holder = pairedHolder(
        _connection,
        Uri.parse('https://host.example.ts.net:8467'),
      );
      final api = _api((request) async {
        asked++;
        return http.Response('{"service":"anythingllm-bridge"}', 200);
      }, holder: holder);
      await api.features();
      await api.features();
      expect(asked, 1);
      await api.features(again: true);
      expect(asked, 2);
      holder
        ..current = const Connection(
          baseUrl: 'https://other.example:3001',
          apiKey: 'K',
        )
        ..companions = {
          toolkitCompanion.code: Uri.parse('https://other.example:8467'),
        };
      await api.features();
      expect(asked, 3);
    });

    test(
      'is null with no server or at a public http address, without asking',
      () async {
        var asked = 0;
        Future<http.Response> count(http.Request _) async {
          asked++;
          return http.Response('{"service":"anythingllm-bridge"}', 200);
        }

        expect(
          await _api(count, holder: ConnectionHolder()).features(),
          isNull,
        );
        expect(
          await _api(
            count,
            holder: ConnectionHolder(_connection)
              ..companions = {
                toolkitCompanion.code: Uri.parse('http://toolkit.example.com'),
              },
          ).features(),
          isNull,
        );
        expect(asked, 0);
      },
    );

    test('with no address said, is asked on the server\'s own origin, and is '
        'absent where anything else answers there', () async {
      final seen = <Uri>[];
      var body = '{"service":"anywherellm-bridge","allow":[]}';
      final api = _api((request) async {
        seen.add(request.url);
        return http.Response(body, 200);
      }, holder: ConnectionHolder(_connection));
      expect(await api.features(), isNotNull);
      expect(
        seen.single.toString(),
        'https://host.example.ts.net:3001/anywherellm-bridge/health',
      );
      body = '<!doctype html><title>AnythingLLM</title>';
      expect(
        await api.features(again: true),
        isNull,
        reason: 'AnythingLLM answers its own page for a path it does not know',
      );
    });

    test('is asked at the address said, under its path', () async {
      final seen = <Uri>[];
      final api = _api(
        (request) async {
          seen.add(request.url);
          return http.Response('{"service":"anythingllm-bridge"}', 200);
        },
        holder: ConnectionHolder(_connection)
          ..companions = {
            toolkitCompanion.code: Uri.parse('http://toolkit.lan/v2'),
          },
      );
      expect(await api.features(), isNotNull);
      expect(seen.single.toString(), 'http://toolkit.lan/v2/health');
    });
  });

  group('calls', () {
    test(
      'send the key, and a refused one says so in the toolkit\'s name',
      () async {
        final seen = <http.Request>[];
        final api = _api((request) async {
          seen.add(request);
          return http.Response(jsonEncode({'error': 'bad key'}), 401);
        });
        final error = await _failure(api.memorySwitches());
        expect(seen.single.headers['Authorization'], 'Bearer SECRET-KEY');
        expect(error.message, 'The toolkit did not accept the key.');
        expect(error.message, isNot(contains('SECRET-KEY')));
      },
    );

    test(
      'a failure ends with one full stop, or the mark it ended with',
      () async {
        for (final (said, shown) in [
          ('not allowed', 'Not allowed.'),
          ('Not allowed.', 'Not allowed.'),
          ('is it on?', 'Is it on?'),
          ('stop it!', 'Stop it!'),
        ]) {
          final error = await _failure(
            _answering({'error': said}, status: 400).scheduledJobs(),
          );
          expect(error.message, shown);
        }
      },
    );

    test('a bare 404 says the status', () async {
      final api = _api((_) async => http.Response('Not Found', 404));
      final error = await _failure(api.savedMemories('home'));
      expect(error.status, 404);
      expect(error.message, 'The toolkit answered HTTP 404.');
    });

    test('an answer that is not JSON fails in plain words', () async {
      final api = _api((_) async => http.Response('<html></html>', 200));
      expect(
        (await _failure(api.scheduledJobs())).message,
        'The toolkit did not answer with JSON.',
      );
    });

    test('a server out of reach is named, without the key', () async {
      final api = _api((_) async => throw const SocketException('refused'));
      final error = await _failure(api.memorySwitches());
      expect(error.message, contains('the toolkit on host.example.ts.net'));
      expect(error.message, isNot(contains('SECRET-KEY')));
    });

    test('any other failure is named without its text', () async {
      final api = _api(
        (request) async => throw FormatException(
          'Invalid HTTP header field value: "${request.headers['Authorization']}"',
        ),
      );
      final error = await _failure(api.memorySwitches());
      expect(error.message, 'Could not reach the toolkit.');
      expect(error.message, isNot(contains('SECRET-KEY')));
    });
  });

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

  test('pages: true in /health makes the pages a feature', () async {
    final toolkit = _Toolkit()..routes['/health'] = {..._health, 'pages': true};
    expect(await toolkit.api().features(), {ToolkitFeature.pages});
    toolkit.routes['/health'] = {..._health, 'pages': 'yes'};
    expect(await toolkit.api().features(), isEmpty);
    toolkit.routes['/health'] = _health;
    expect(await toolkit.api().features(), isEmpty);
  });

  group('the pages', () {
    test('are read with the key and decoded', () async {
      final toolkit = _Toolkit()
        ..routes['/pages'] = {
          'library': '/library-lean/aB3.html',
          'vault': null,
        };
      final pages = await toolkit.api().pages();
      expect(pages, {SkillPage.library: '/library-lean/aB3.html'});
      final request = toolkit.seen.single;
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://host.example.ts.net:8467/pages');
      expect(request.headers['Authorization'], 'Bearer SECRET-KEY');
    });

    test('are refused with the status the bridge gave', () async {
      final toolkit = _Toolkit()
        ..routes['/pages'] = http.Response(
          jsonEncode({'error': 'That key may not read this.'}),
          403,
        );
      final error = await _failure(toolkit.api().pages());
      expect(error.status, 403);
      expect(error.message, isNot(contains('SECRET-KEY')));
    });
  });

  group('scheduled jobs', () {
    const draft = JobDraft(
      name: 'Brief',
      prompt: 'Summarise today.',
      cron: '0 7 * * *',
    );

    test('a job\'s newest runs are listed, newest first', () async {
      final toolkit = _Toolkit()
        ..routes['/scheduled-jobs/7/runs'] = {
          'runs': [
            {'status': 'running'},
            {'status': 'failed', 'error': 'The site answered 503'},
            for (var n = 0; n < 10; n++) {'status': 'completed'},
          ],
        };
      final runs = await toolkit.api().jobRuns('7');
      expect(runs, hasLength(runsRead));
      expect(runs.take(2).map((r) => r.status), ['running', 'failed']);
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
