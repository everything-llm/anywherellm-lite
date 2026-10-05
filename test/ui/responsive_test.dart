import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:everything/core/models.dart';
import 'package:everything/ui/sidebar.dart';
import 'package:everything/ui/state/nav_controller.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// One width per shell layout, and the window's own minimum (see my_application.cc).
const sizes = [Size(1400, 900), Size(780, 700), Size(500, 700), Size(360, 480)];

const longWord =
    'an-extremely-long-unbroken-name-that-has-no-place-to-wrap-and-must-not-overflow-anything';
const longPath = 'folder-$longWord/file-$longWord.md';

/// Data that stresses every layout: long unbroken words, many badges, long commands.
FakeApi awkward() {
  final meta = sampleMeta(
    summary: 'A summary that keeps going. ' * 12,
    tags: ['tag-$longWord', 'b', 'c', 'd', 'e', 'f', 'g', 'h'],
  );
  return FakeApi()
    ..overviewValue = sampleOverview(
      findings: [
        Finding(
          library: 'research',
          path: longPath,
          message: 'message $longWord',
          severity: 'error',
        ),
      ],
    )
    ..researchValue = [ResearchEntry(path: longPath, meta: meta)]
    ..researchDocs = {
      longPath: ResearchDoc(
        path: longPath,
        text: 'text $longWord\n' * 40,
        meta: meta,
      ),
    }
    ..skillsValue = [
      SkillMeta(
        name: 'skill-$longWord',
        description: 'description $longWord',
        topic: 'topic-$longWord',
        tags: ['t-$longWord', 'x'],
      ),
    ]
    ..skillDocs = {
      'skill-$longWord': SkillDoc(
        name: 'skill-$longWord',
        text: 'body $longWord',
        meta: SkillMeta(
          name: 'skill-$longWord',
          description: 'description $longWord',
          topic: 'topic-$longWord',
          tags: ['t-$longWord'],
        ),
      ),
    }
    ..inboxValue = ['staged-$longWord.md', 'b.md', 'c.md', 'd.md'];
}

void main() {
  final routes = <String, AppRoute>{
    'research list': const ResearchListRoute(),
    'research doc': const ResearchDocRoute(longPath),
    'skills list': const SkillsListRoute(),
    'skill doc': const SkillDocRoute('skill-$longWord'),
    'inbox': const InboxRoute(),
    'settings': const SettingsRoute(),
  };

  for (final size in sizes) {
    for (final MapEntry(key: name, value: route) in routes.entries) {
      testWidgets(
        '$name fits at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await pumpApp(tester, api: awkward(), size: size, route: route);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('resizing through every layout keeps working', (tester) async {
    final h = await pumpApp(
      tester,
      api: awkward(),
      size: sizes.first,
      route: const ResearchListRoute(),
    );
    for (final size in [...sizes, ...sizes.reversed]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'at ${size.width}');
    }
    expect(h.nav.route, const ResearchListRoute());
    expect(find.byType(Sidebar), findsOneWidget);
  });
}
