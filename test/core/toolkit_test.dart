import 'package:anywherellm/core/toolkit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_toolkit.dart';

List<BridgeRule> _rules(List<String> allow) => bridgeRules({'allow': allow});

void main() {
  group('a bridge rule', () {
    test('matches whole segments, under its method or any', () {
      final rule = BridgeRule.parse('/workspaces')!;
      expect(rule.method, isNull);
      expect(rule.permits('GET', '/workspaces'), isTrue);
      expect(rule.permits('POST', '/workspaces/home/memories'), isTrue);
      expect(rule.permits('GET', '/workspaces-old'), isFalse);
      expect(rule.permits('GET', '/workspace/home'), isFalse);

      final get = BridgeRule.parse('get /admin/system-preferences-for')!;
      expect(get.method, 'GET');
      expect(get.permits('GET', '/admin/system-preferences-for'), isTrue);
      expect(get.permits('POST', '/admin/system-preferences-for'), isFalse);
      expect(get.permits('GET', '/admin'), isFalse);
    });

    test('a * takes any one segment', () {
      final rule = BridgeRule.parse('GET /workspace/*/thread/*/chats')!;
      expect(rule.permits('GET', '/workspace/a/thread/b/chats'), isTrue);
      expect(rule.permits('GET', '/workspace/a/thread/b/chats/c'), isTrue);
      expect(rule.permits('GET', '/workspace/a/chats'), isFalse);
      expect(rule.permits('GET', '/workspace/a/thread'), isFalse);
    });

    test('is none for what the toolkit would not read as one', () {
      for (final entry in [
        '',
        '/',
        'workspaces',
        'PATCH /x',
        '/a//b',
        '/a/../b',
      ]) {
        expect(BridgeRule.parse(entry), isNull, reason: entry);
      }
      expect(_rules(['/memories', 'nonsense']), hasLength(1));
      expect(
        bridgeRules({
          'features': ['memories'],
        }),
        isEmpty,
      );
      expect(bridgeRules(null), isEmpty);
    });

    test('never lets a climbing path through', () {
      expect(
        BridgeRule.parse('/scheduled-jobs')!
            .permits('GET', '/scheduled-jobs/../system'),
        isFalse,
      );
    });
  });

  group('the features a bridge lets through', () {
    test('the line Lite asks for passes every feature a route serves', () {
      expect(bridgeFeatures(_rules(liteBridgeAllow.split(','))), {
        ToolkitFeature.memories,
        ToolkitFeature.jobs,
        ToolkitFeature.jobsWrite,
      });
    });

    test('rules narrowed with * still pass their features', () {
      expect(
        bridgeFeatures(
          _rules([
            '/workspaces/*/memories',
            '/memories',
            'GET /admin/system-preferences-for',
            'POST /admin/system-preferences',
          ]),
        ),
        {ToolkitFeature.memories},
      );
    });

    test('nothing passes nothing', () {
      expect(bridgeFeatures(const []), isEmpty);
    });

    test('jobs read only, without the routes that change them', () {
      expect(bridgeFeatures(_rules(['GET /scheduled-jobs'])), {
        ToolkitFeature.jobs,
      });
    });

    test('a feature with one call missing is not served', () {
      expect(
        bridgeFeatures(
          _rules([
            '/workspaces',
            '/memories',
            'GET /admin/system-preferences-for',
          ]),
        ),
        isEmpty,
      );
    });
  });

  test(
    'a companion\'s address kept under a /health name moves to its code',
    () {
      expect(companionKey('anythingllm-toolkit'), toolkitCompanion.code);
      expect(companionKey('anythingllm-bridge'), toolkitCompanion.code);
      expect(companionKey('anywherellm-bridge'), toolkitCompanion.code);
      expect(companionKey('toolkit'), 'toolkit');
      expect(companionKey('other'), 'other');
    },
  );
}
