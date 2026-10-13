import 'dart:convert';

import 'package:anywherellm/core/apps.dart';
import 'package:anywherellm/core/push.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pushTargetOf', () {
    test('AnythingLLM\'s scheduled-job push opens Upcoming', () {
      final payload = jsonEncode({
        'title': 'Morning brief completed',
        'body': 'Three things today',
        'data': {'onClickUrl': '/settings/scheduled-jobs/4/runs/9'},
      });
      expect(pushTargetOf(payload, PushSource.server), const UpcomingTarget());
    });

    test('an app\'s push opens that app', () {
      final payload = jsonEncode({
        'title': 'Pomodoro',
        'body': 'Break time',
        'data': {
          'onClickUrl': 'https://gir:8465/home/pomodoro/',
          'workspace': 'home',
          'app': 'pomodoro',
          'ev': 'phase-end',
        },
      });
      expect(
        pushTargetOf(payload, PushSource.apps),
        const AppTarget(AppRef('home', 'pomodoro')),
      );
    });

    test('an app\'s push that names no app, or not one, opens nothing', () {
      for (final data in [
        {'workspace': 'home'},
        {'workspace': 'home', 'app': '../etc'},
        {'workspace': '', 'app': 'pomodoro'},
      ]) {
        final payload = jsonEncode({'title': 'x', 'data': data});
        expect(pushTargetOf(payload, PushSource.apps), isNull);
      }
      expect(pushTargetOf('not json', PushSource.apps), isNull);
    });
  });

  test(
    'a subscription is the browser\'s JSON and never prints its endpoint',
    () {
      const sub = PushSubscription(
        'https://ntfy.sh/upSecret',
        p256dh: 'BK',
        auth: 'A',
      );
      expect(sub.toJson(), {
        'endpoint': 'https://ntfy.sh/upSecret',
        'keys': {'p256dh': 'BK', 'auth': 'A'},
      });
      expect('$sub', isNot(contains('upSecret')));
    },
  );

  test('sources are found by their instance', () {
    expect(PushSource.ofInstance('anythingllm'), PushSource.server);
    expect(PushSource.ofInstance('apps'), PushSource.apps);
    expect(PushSource.ofInstance('other'), isNull);
  });

  test('a distributor is named by its package', () {
    expect(distributorName('io.heckel.ntfy'), 'ntfy');
    expect(distributorName('com.example.push'), 'com.example.push');
  });
}
