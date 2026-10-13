import 'dart:convert';

import 'package:anywherellm/adapters/toolkit_client.dart';
import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _connection = Connection(
  baseUrl: 'https://host.example.ts.net:3001',
  apiKey: 'SECRET-KEY',
);

const _health = {
  'ok': true,
  'service': 'anythingllm-toolkit',
  'features': ['models', 'memories', 'jobs'],
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
  test('its features are what its health names', () async {
    final toolkit = _Toolkit();
    expect(await toolkit.api().features(), {
      'models',
      ToolkitFeature.memories,
      ToolkitFeature.jobs,
    });
    expect(toolkit.seen.single.url.port, 8467);
  });

  group('saved memories', () {
    test('the switches are read and written', () async {
      final toolkit = _Toolkit()
        ..routes['/memory-switches'] = {'enabled': true, 'learn': false};
      final api = toolkit.api();
      final switches = await api.memorySwitches();
      expect((switches.enabled, switches.learn), (true, false));
      await api.setMemorySwitches(learn: true);
      expect(toolkit.seen.last.method, 'PUT');
      expect(jsonDecode(toolkit.seen.last.body), {'learn': true});
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
          ..routes['/memories/7/move'] = {
            'memory': {...memory, 'scope': 'workspace'},
          };
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
        expect(jsonDecode(toolkit.seen.last.body), {'workspace': 'q3'});

        await api.deleteMemory(7);
        expect(toolkit.seen.last.method, 'DELETE');
        expect(toolkit.seen.last.url.path, '/memories/7');
      },
    );

    test('a refusal fails in the toolkit\'s words, without the key', () async {
      final toolkit = _Toolkit()
        ..routes['/workspaces/q3/memories'] = http.Response(
          jsonEncode({
            'error': 'AnythingLLM turned it down: Maximum global memory limit (5) reached.',
          }),
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
      ..routes['/jobs'] = {
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
