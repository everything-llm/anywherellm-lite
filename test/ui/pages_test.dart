import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything/core/models.dart';
import 'package:everything/core/ports.dart';
import 'package:everything/ui/state/nav_controller.dart';
import 'package:everything/ui/widgets/chip.dart';
import 'package:everything/ui/widgets/rows.dart';
import 'package:everything/ui/widgets/select.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

ResearchEntry entry(
  String path, {
  String status = 'current',
  String verified = 'human',
}) => ResearchEntry(
  path: path,
  meta: sampleMeta(
    summary: 'About $path',
    status: status,
    verified: verified,
    tags: const [],
  ),
);

/// The field in the All tags panel.
final tagField = find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == 'Find a tag',
);

/// The page's own scrollable, not the sidebar's.
final pageScroll = find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  group('overview', () {
    testWidgets('counts each library and says where the server keeps things', (
      tester,
    ) async {
      await pumpApp(tester, route: const OverviewRoute());
      expect(find.text('3 documents, 2 tags, 1 topic'), findsOneWidget);
      expect(find.text('1 skill, 0 tags, 0 topics'), findsOneWidget);
      expect(find.text('1 error'), findsOneWidget);
      expect(find.text('/repo/storage/data/research'), findsOneWidget);
      expect(find.text('/repo/storage/inbox'), findsOneWidget);
      expect(find.text('storage/PROMPT.md'), findsOneWidget);
    });

    testWidgets('lists what the last check found, with the library', (
      tester,
    ) async {
      final api = FakeApi()
        ..overviewValue = sampleOverview(
          findings: const [
            Finding(
              library: 'skills',
              path: 'demo',
              message: 'no topic',
              severity: 'warning',
            ),
          ],
        );
      await pumpApp(tester, api: api, route: const OverviewRoute());
      expect(find.text('To look at'), findsOneWidget);
      expect(find.text('skills: no topic'), findsOneWidget);
    });

    testWidgets('has no list of findings when the libraries are clean', (
      tester,
    ) async {
      await pumpApp(tester, route: const OverviewRoute());
      expect(find.text('To look at'), findsNothing);
    });

    testWidgets('a library opens its list', (tester) async {
      final h = await pumpApp(tester, route: const OverviewRoute());
      await tester.tap(find.text('3 documents, 2 tags, 1 topic'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const ResearchListRoute());
    });

    testWidgets('keeps what it knew when asking again fails', (tester) async {
      final api = FakeApi()
        ..errors['overview'] = const ApiException('server down', status: 500);
      await pumpApp(tester, api: api, route: const OverviewRoute());
      expect(api.calls, contains('overview'));
      expect(find.text('3 documents, 2 tags, 1 topic'), findsOneWidget);
      expect(find.text('Could not load this page'), findsNothing);
    });
  });

  group('lists', () {
    ResearchEntry doc(
      String path, {
      String kind = 'note',
      List<String> tags = const [],
    }) => ResearchEntry(
      path: path,
      meta: sampleMeta(summary: 'About $path', kind: kind, tags: tags),
    );

    FakeApi library() => FakeApi()
      ..researchValue = [
        doc('ai/agents.md', kind: 'report', tags: ['ai', 'evidence']),
        doc('ai/models.md', kind: 'report', tags: ['ai']),
        doc('ops/deploy.md', kind: 'template', tags: ['ops']),
        doc('ops/spec.md', kind: 'spec', tags: ['evidence']),
      ];

    testWidgets('the count says how many there are', (tester) async {
      await pumpApp(tester, api: library(), route: const ResearchListRoute());
      expect(find.text('4 documents'), findsOneWidget);
      expect(find.text('Clear filters'), findsNothing);
    });

    testWidgets('a search narrows the list and can be cleared', (tester) async {
      await pumpApp(tester, api: library(), route: const ResearchListRoute());
      await tester.enterText(find.byType(TextField), 'DEPLOY');
      await tester.pumpAndSettle();
      expect(find.text('About ops/deploy.md'), findsOneWidget);
      expect(find.text('About ai/agents.md'), findsNothing);
      expect(find.text('Showing 1 of 4 documents'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('About ai/agents.md'), findsOneWidget);
      expect(find.text('4 documents'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('the type select narrows to one kind', (tester) async {
      await pumpApp(tester, api: library(), route: const ResearchListRoute());
      await tester.tap(find.byType(NilsSelect));
      await tester.pumpAndSettle();
      await tester.tap(find.text('report (2)'));
      await tester.pumpAndSettle();
      expect(find.text('About ai/agents.md'), findsOneWidget);
      expect(find.text('About ai/models.md'), findsOneWidget);
      expect(find.text('About ops/deploy.md'), findsNothing);
      expect(find.text('Showing 2 of 4 documents'), findsOneWidget);
    });

    testWidgets('a tag chip narrows the list, and two must both match', (
      tester,
    ) async {
      await pumpApp(tester, api: library(), route: const ResearchListRoute());
      await tester.tap(find.widgetWithText(NilsChip, 'evidence'));
      await tester.pumpAndSettle();
      expect(find.text('About ai/agents.md'), findsOneWidget);
      expect(find.text('About ops/spec.md'), findsOneWidget);
      expect(find.text('About ai/models.md'), findsNothing);
      await tester.tap(find.widgetWithText(NilsChip, 'ai'));
      await tester.pumpAndSettle();
      expect(find.text('About ai/agents.md'), findsOneWidget);
      expect(find.text('About ops/spec.md'), findsNothing);
      expect(find.text('Showing 1 of 4 documents'), findsOneWidget);
    });

    testWidgets('a filter that matches nothing says so', (tester) async {
      await pumpApp(tester, api: library(), route: const ResearchListRoute());
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches'), findsOneWidget);
      expect(
        find.text('Try fewer words, or clear the filters.'),
        findsOneWidget,
      );
      expect(find.text('Showing 0 of 4 documents'), findsOneWidget);
    });

    testWidgets('a long tag list folds behind All tags and can be searched', (
      tester,
    ) async {
      final api = FakeApi()
        ..researchValue = [
          doc('a.md', tags: [for (var i = 0; i < 12; i++) 'topic-$i']),
        ];
      await pumpApp(tester, api: api, route: const ResearchListRoute());
      expect(find.widgetWithText(NilsChip, 'topic-9'), findsNothing);
      await tester.tap(find.text('All tags (12)'));
      await tester.pumpAndSettle();
      expect(find.text('Hide all tags'), findsOneWidget);
      expect(find.widgetWithText(NilsChip, 'topic-9'), findsOneWidget);
      await tester.enterText(tagField, 'topic-1');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(NilsChip, 'topic-9'), findsNothing);
      await tester.enterText(tagField, 'nope');
      await tester.pumpAndSettle();
      expect(find.text('No tag matches "nope".'), findsOneWidget);
      await tester.tap(find.text('Hide all tags'));
      await tester.pumpAndSettle();
      expect(find.text('Hide all tags'), findsNothing);
    });

    testWidgets('a pressed tag below the top ones stays on show', (
      tester,
    ) async {
      final api = FakeApi()
        ..researchValue = [
          doc('a.md', tags: [for (var i = 0; i < 12; i++) 'topic-$i']),
        ];
      await pumpApp(tester, api: api, route: const ResearchListRoute());
      await tester.tap(find.text('All tags (12)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(NilsChip, 'topic-9').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide all tags'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(NilsChip, 'topic-9'), findsOneWidget);
    });

    testWidgets('a filtered tag shows in the accent on its rows', (
      tester,
    ) async {
      await pumpApp(tester, api: library(), route: const ResearchListRoute());
      await tester.tap(find.widgetWithText(NilsChip, 'ops'));
      await tester.pumpAndSettle();
      expect(find.text('About ops/deploy.md'), findsOneWidget);
      expect(find.text('About ai/agents.md'), findsNothing);
    });

    testWidgets('an empty library has no filters', (tester) async {
      await pumpApp(tester, route: const ResearchListRoute());
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(NilsSelect), findsNothing);
    });

    testWidgets(
      'this library\'s findings sit above the list, and only its own',
      (tester) async {
        final api = library()
          ..overviewValue = sampleOverview(
            findings: const [
              Finding(
                library: 'research',
                path: 'ai/x.md',
                message: 'summary is empty',
                severity: 'error',
              ),
              Finding(
                library: 'skills',
                path: 'lint',
                message: 'no topic',
                severity: 'warning',
              ),
            ],
          );
        await pumpApp(tester, api: api, route: const ResearchListRoute());
        expect(find.text('To look at'), findsOneWidget);
        expect(find.text('ai/x.md'), findsOneWidget);
        expect(find.text('summary is empty'), findsOneWidget);
        expect(find.text('error'), findsOneWidget);
        expect(find.text('no topic'), findsNothing);
      },
    );

    testWidgets('opening a list runs the checks again', (tester) async {
      final api = library();
      await pumpApp(tester, api: api, route: const ResearchListRoute());
      expect(api.calls.where((c) => c == 'overview'), hasLength(1));
    });

    testWidgets('the skills topic select narrows by topic', (tester) async {
      final api = FakeApi()
        ..skillsValue = [
          const SkillMeta(
            name: 'alpha',
            description: 'A',
            topic: 'writing',
            tags: ['md'],
          ),
          const SkillMeta(
            name: 'beta',
            description: 'B',
            topic: 'python',
            tags: [],
          ),
        ];
      await pumpApp(tester, api: api, route: const SkillsListRoute());
      expect(find.text('2 skills'), findsOneWidget);
      await tester.tap(find.byType(NilsSelect));
      await tester.pumpAndSettle();
      await tester.tap(find.text('python (1)'));
      await tester.pumpAndSettle();
      expect(find.text('beta'), findsWidgets);
      expect(find.text('alpha'), findsNothing);
      expect(find.text('Search skills'), findsOneWidget);
    });
  });

  group('research', () {
    testWidgets('the list groups by first folder with badges', (tester) async {
      final api = FakeApi()
        ..researchValue = [
          entry('ai/agents.md'),
          entry('ai/models.md', status: 'stale', verified: 'none'),
          entry('top.md'),
        ];
      await pumpApp(tester, api: api, route: const ResearchListRoute());
      expect(find.text('Research'), findsWidgets);
      expect(find.text('ai'), findsOneWidget);
      expect(find.text('(root)'), findsOneWidget);
      expect(find.text('agents'), findsOneWidget);
      expect(find.text('models'), findsOneWidget);
      expect(find.text('About ai/agents.md'), findsOneWidget);
      expect(find.text('stale'), findsOneWidget);
      expect(find.text('unverified'), findsOneWidget);
      expect(find.text('note'), findsNWidgets(3));
    });

    testWidgets('an empty library explains how to add one', (tester) async {
      await pumpApp(tester, route: const ResearchListRoute());
      expect(find.text('No research yet'), findsOneWidget);
      expect(
        find.text(
          'Stage a markdown file in the Inbox, then file it with nils chat or nils research add.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a row opens the document', (tester) async {
      final api = FakeApi()
        ..researchValue = [entry('ai/agents.md')]
        ..researchDocs = {
          'ai/agents.md': ResearchDoc(
            path: 'ai/agents.md',
            text: '# Agents\nbody',
            meta: sampleMeta(),
          ),
        };
      final h = await pumpApp(
        tester,
        api: api,
        route: const ResearchListRoute(),
      );
      await tester.tap(find.text('agents'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const ResearchDocRoute('ai/agents.md'));
      expect(api.calls, contains('researchDoc:ai/agents.md'));
      expect(find.text('# Agents\nbody'), findsOneWidget);
    });

    testWidgets(
      'a document shows its front matter and no warning when trustworthy',
      (tester) async {
        final api = FakeApi()
          ..researchDocs = {
            'ai/agents.md': ResearchDoc(
              path: 'ai/agents.md',
              text: 'TEXT',
              meta: sampleMeta(tags: const ['ai', 'x']),
            ),
          };
        await pumpApp(
          tester,
          api: api,
          route: const ResearchDocRoute('ai/agents.md'),
        );
        expect(find.text('agents'), findsOneWidget);
        expect(find.text('A summary.'), findsOneWidget);
        expect(find.text('ai'), findsWidgets);
        expect(find.text('Type'), findsOneWidget);
        expect(find.text('2026-01-02'), findsOneWidget);
        expect(find.text('claude'), findsOneWidget);
        expect(find.text('1 link(s)'), findsOneWidget);
        expect(find.text('Say so before relying on this'), findsNothing);
        expect(find.text('TEXT'), findsOneWidget);
      },
    );

    testWidgets('an unverified stale document warns', (tester) async {
      final api = FakeApi()
        ..researchDocs = {
          'a.md': ResearchDoc(
            path: 'a.md',
            text: 'T',
            meta: sampleMeta(status: 'stale', verified: 'none'),
          ),
        };
      await pumpApp(tester, api: api, route: const ResearchDocRoute('a.md'));
      expect(find.text('Say so before relying on this'), findsOneWidget);
      expect(
        find.text('Its status is stale and it is unverified.'),
        findsOneWidget,
      );
    });

    testWidgets('unreadable front matter is an error with the way to see why', (
      tester,
    ) async {
      final api = FakeApi()
        ..researchDocs = {'a.md': const ResearchDoc(path: 'a.md', text: 'RAW')};
      await pumpApp(tester, api: api, route: const ResearchDocRoute('a.md'));
      expect(find.text('The front matter could not be read'), findsOneWidget);
      expect(
        find.text('Run nils research check for the reason.'),
        findsOneWidget,
      );
      expect(find.text('RAW'), findsOneWidget);
    });

    testWidgets('the breadcrumb goes back to the list', (tester) async {
      final api = FakeApi()
        ..researchDocs = {
          'ai/deep/a.md': ResearchDoc(
            path: 'ai/deep/a.md',
            text: 'T',
            meta: sampleMeta(),
          ),
        };
      final h = await pumpApp(
        tester,
        api: api,
        route: const ResearchDocRoute('ai/deep/a.md'),
      );
      expect(find.text('ai / deep'), findsOneWidget);
      await tester.tap(find.text('Research').last);
      await tester.pumpAndSettle();
      expect(h.nav.route, const ResearchListRoute());
    });

    testWidgets('a missing document shows the 404', (tester) async {
      final api = FakeApi()
        ..errors['researchDoc'] = const ApiException(
          'no such document',
          status: 404,
        );
      await pumpApp(tester, api: api, route: const ResearchDocRoute('gone.md'));
      expect(find.text('no such document'), findsOneWidget);
    });
  });

  group('skills', () {
    SkillMeta skill(
      String name, {
      String? topic,
      List<String> tags = const [],
    }) => SkillMeta(
      name: name,
      description: 'Does $name',
      topic: topic,
      tags: tags,
    );

    testWidgets(
      'the list groups by topic, with unclassified last as it arrives',
      (tester) async {
        final api = FakeApi()
          ..skillsValue = [
            skill('alpha', topic: 'writing', tags: const ['md']),
            skill('beta'),
            skill('gamma', topic: 'writing'),
          ];
        await pumpApp(tester, api: api, route: const SkillsListRoute());
        expect(find.text('writing'), findsOneWidget);
        expect(find.text('unclassified'), findsOneWidget);
        expect(find.text('alpha'), findsOneWidget);
        expect(find.text('Does beta'), findsOneWidget);
        // The chip that filters by it, and the badge on its row.
        expect(find.text('md'), findsNWidgets(2));
      },
    );

    testWidgets('an empty library explains how to add one', (tester) async {
      await pumpApp(tester, route: const SkillsListRoute());
      expect(find.text('No skills yet'), findsOneWidget);
    });

    testWidgets('a row opens the skill', (tester) async {
      final api = FakeApi()
        ..skillsValue = [skill('alpha', topic: 'writing')]
        ..skillDocs = {
          'alpha': SkillDoc(
            name: 'alpha',
            text: 'SKILL BODY',
            meta: skill('alpha', topic: 'writing'),
          ),
        };
      final h = await pumpApp(tester, api: api, route: const SkillsListRoute());
      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const SkillDocRoute('alpha'));
      expect(find.text('SKILL BODY'), findsOneWidget);
      expect(find.text('Topic'), findsOneWidget);
      expect(find.text('writing'), findsOneWidget);
      expect(find.text('unknown'), findsOneWidget);
    });

    testWidgets('a skill without a topic is unclassified', (tester) async {
      final api = FakeApi()
        ..skillDocs = {'a': SkillDoc(name: 'a', text: 'T', meta: skill('a'))};
      await pumpApp(tester, api: api, route: const SkillDocRoute('a'));
      expect(find.text('unclassified'), findsOneWidget);
      expect(find.text('none'), findsOneWidget);
    });

    testWidgets('a skill without readable metadata is an error', (
      tester,
    ) async {
      final api = FakeApi()
        ..skillDocs = {'b': const SkillDoc(name: 'b', text: 'RAW')};
      await pumpApp(tester, api: api, route: const SkillDocRoute('b'));
      expect(find.text('The front matter could not be read'), findsOneWidget);
      expect(
        find.text('Run nils skills check for the reason.'),
        findsOneWidget,
      );
    });
  });

  group('long lists', () {
    testWidgets('the research list builds only the rows near the screen', (
      tester,
    ) async {
      final api = FakeApi()
        ..researchValue = [
          for (var i = 0; i < 300; i++)
            entry('area/doc${i.toString().padLeft(3, '0')}.md'),
        ];
      await pumpApp(tester, api: api, route: const ResearchListRoute());
      expect(find.text('doc000'), findsOneWidget);
      expect(find.text('doc299'), findsNothing);
      expect(
        find.byType(NilsRow).evaluate().length,
        lessThan(60),
        reason: 'the rest are built as they scroll into view',
      );
      await tester.scrollUntilVisible(
        find.text('doc299'),
        600,
        scrollable: pageScroll,
      );
      expect(find.text('doc299'), findsOneWidget);
      expect(find.text('doc000'), findsNothing);
    });

    testWidgets('the skills list builds lazily too, across topics', (
      tester,
    ) async {
      final api = FakeApi()
        ..skillsValue = [
          for (var i = 0; i < 300; i++)
            SkillMeta(
              name: 'skill${i.toString().padLeft(3, '0')}',
              description: 'Does it',
              topic: i < 150 ? 'first' : 'second',
              tags: const [],
            ),
        ];
      await pumpApp(tester, api: api, route: const SkillsListRoute());
      expect(find.text('first'), findsOneWidget);
      expect(find.text('skill000'), findsOneWidget);
      expect(find.text('skill299'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('skill299'),
        600,
        scrollable: pageScroll,
      );
      expect(find.text('skill299'), findsOneWidget);
      expect(find.text('skill000'), findsNothing);
      expect(find.text('first'), findsNothing);
    });

    testWidgets('a tap on a row far down the list opens it', (tester) async {
      final api = FakeApi()
        ..researchValue = [
          for (var i = 0; i < 300; i++)
            entry('area/doc${i.toString().padLeft(3, '0')}.md'),
        ]
        ..researchDocs = {
          'area/doc250.md': ResearchDoc(
            path: 'area/doc250.md',
            text: 'BODY 250',
            meta: sampleMeta(),
          ),
        };
      final h = await pumpApp(
        tester,
        api: api,
        route: const ResearchListRoute(),
      );
      await tester.scrollUntilVisible(
        find.text('doc250'),
        600,
        scrollable: pageScroll,
      );
      await tester.tap(find.text('doc250'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const ResearchDocRoute('area/doc250.md'));
      expect(find.text('BODY 250'), findsOneWidget);
    });
  });
}
