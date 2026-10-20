import 'package:anywherellm/core/asks.dart';
import 'package:anywherellm/core/chat.dart';
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

  test('a request without its id, host, workspace or end is none', () {
    for (final key in ['id', 'host', 'workspace', 'expires']) {
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

  test('the addresses always allowed are read, an empty one left out', () {
    final origins = allowedOriginsOf({
      'origins': [
        {'origin': 'http://muse-vm:8463', 'added': '2026-10-20T10:01:00Z'},
        {'origin': 'https://nas.lan'},
        {'origin': ''},
        'http://muse-vm:8463',
      ],
    });
    expect(
      [for (final o in origins) o.origin],
      ['http://muse-vm:8463', 'https://nas.lan'],
    );
    expect(origins.first.added, DateTime.utc(2026, 10, 20, 10, 1));
    expect(origins.last.added, isNull);
    expect(
      allowedOriginsOf({
        'hosts': [
          {'host': 'muse-vm'},
        ],
      }),
      isEmpty,
    );
    expect(allowedOriginsOf(null), isEmpty);
  });

  test('a status line names the request it waits on, and shows without it', () {
    const thought =
        'Waiting for your approval in AnywhereLLM to reach muse-vm [ask:$_id]';
    final status = statusOf(thought);
    expect(status.ask, _id);
    expect(
      status.text,
      'Waiting for your approval in AnywhereLLM to reach muse-vm',
    );
    expect(statusOf('Running web-browsing').ask, isNull);
    expect(statusOf('[ask:$_id] then more').ask, isNull);
    expect(statusOf('reach x [ask:0123]').ask, isNull);
  });
}
