import 'package:anywherellm/core/asks.dart';
import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = '0123456789abcdef0123456789abcdef';

const _ask = {
  'id': _id,
  'host': 'muse-vm',
  'origin': 'http://muse-vm:8463',
  'skill': 'Library',
  'workspace': 'home',
  'why': 'Send a request to http://muse-vm:8463',
  'asked': '2026-10-20T10:00:00Z',
  'expires': '2026-10-20T10:02:00Z',
  'decision': null,
};

void main() {
  test('a request is read as the bridge holds it', () {
    final ask = askOf({'ask': _ask})!;
    expect(ask.id, _id);
    expect(ask.origin, 'http://muse-vm:8463');
    expect(ask.skill, 'Library');
    expect(ask.decision, isNull);
    expect(ask.expires, DateTime.utc(2026, 10, 20, 10, 2));
    expect(ask.expiredAt(DateTime.utc(2026, 10, 20, 10, 1)), isFalse);
    expect(ask.expiredAt(DateTime.utc(2026, 10, 20, 10, 2)), isTrue);
    expect(
      askOf({
        'ask': {..._ask, 'decision': 'always'},
      })!.decision,
      AskDecision.always,
    );
  });

  test('a request without its id, host, workspace or times is none', () {
    for (final key in ['id', 'host', 'workspace', 'asked', 'expires']) {
      expect(
        askOf({
          'ask': {..._ask, key: null},
        }),
        isNull,
        reason: key,
      );
    }
    expect(
      askOf({
        'ask': {..._ask, 'id': '../vault'},
      }),
      isNull,
    );
    expect(askOf({'error': 'gone'}), isNull);
  });

  test('the hosts always allowed are read, an empty one left out', () {
    final hosts = allowedHostsOf({
      'hosts': [
        {'host': 'muse-vm', 'added': '2026-10-20T10:01:00Z'},
        {'host': 'nas.lan'},
        {'host': ' '},
        'muse-vm',
      ],
    });
    expect([for (final h in hosts) h.host], ['muse-vm', 'nas.lan']);
    expect(hosts.first.added, DateTime.utc(2026, 10, 20, 10, 1));
    expect(hosts.last.added, isNull);
    expect(allowedHostsOf(null), isEmpty);
  });

  test('a status line names the request it waits on, and shows without it', () {
    const thought =
        'Waiting for your approval in AnywhereLLM to reach muse-vm [ask:$_id]';
    expect(askIdIn(thought), _id);
    expect(
      agentStatus(thought),
      'Waiting for your approval in AnywhereLLM to reach muse-vm',
    );
    expect(askIdIn('Running web-browsing'), isNull);
    expect(askIdIn('[ask:$_id] then more'), isNull);
    expect(askIdIn('reach x [ask:0123]'), isNull);
  });

  test('the bridge says itself that it serves the requests', () {
    expect(bridgeServes({'asks': true}), {ToolkitFeature.asks});
    expect(bridgeServes({'asks': 'yes'}), isEmpty);
    expect(bridgeServes(null), isEmpty);
  });
}
