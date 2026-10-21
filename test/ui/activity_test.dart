import 'package:anywherellm/core/activity.dart';
import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:anywherellm/ui/activity.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_toolkit.dart';
import '../support/pump.dart';

FakeToolkit _serving(Set<String> features) =>
    FakeToolkit()
      ..served = {ToolkitFeature.memories, ToolkitFeature.jobs, ...features};

Future<Harness> _open(
  WidgetTester tester,
  FakeToolkit toolkit, {
  FakeAnythingLlm? llm,
  bool canViewApps = false,
  bool canShare = false,
}) => pumpApp(
  tester,
  llm: llm ?? planningServer(),
  toolkitServer: toolkit,
  shelf: true,
  canViewApps: canViewApps,
  canShare: canShare,
  size: const Size(390, 1000),
);

ActivityEvent _event(
  String title, {
  String id = '',
  Duration ago = Duration.zero,
  ActivityKind kind = ActivityKind.task,
  ActivityOutcome outcome = ActivityOutcome.ok,
  String detail = '',
  ActivityLink? link,
}) => ActivityEvent(
  id: id.isEmpty ? null : id,
  at: DateTime.now().toUtc().subtract(ago),
  title: title,
  kind: kind,
  outcome: outcome,
  workspace: 'Household',
  detail: detail,
  link: link,
);

void main() {
  group('Activity', () {
    FakeToolkit activity(List<ActivityEvent> events) =>
        _serving({ToolkitFeature.activity})..activityEvents = events;

    testWidgets('the card says what failed today', (tester) async {
      await _open(
        tester,
        activity([
          _event('Price watch', outcome: ActivityOutcome.failed),
          _event('Morning brief'),
        ]),
      );
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('1 failed today'), findsOneWidget);
    });

    testWidgets('events group by day and filter to what failed', (
      tester,
    ) async {
      final h = await _open(
        tester,
        activity([
          _event('Price watch', outcome: ActivityOutcome.failed),
          _event('Morning brief'),
          _event('Old brief', ago: const Duration(hours: 30)),
        ]),
      );
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(h.shell.toolkitPage, ToolkitPage.activity);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('Price watch'), findsOneWidget);
      expect(find.text('Old brief'), findsOneWidget);
      expect(find.text('Failed'), findsWidgets);
      await tester.tap(control('Failed'));
      await tester.pumpAndSettle();
      expect(find.text('Price watch'), findsOneWidget);
      expect(find.text('Morning brief'), findsNothing);
      expect(find.text('Old brief'), findsNothing);
    });

    testWidgets('older events come on Show more', (tester) async {
      final toolkit = activity([
        _event('One', id: 'a'),
        _event('Two', id: 'b'),
        _event('Three', id: 'c'),
      ])..activityPageSize = 2;
      await _open(tester, toolkit);
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(find.text('Three'), findsNothing);
      await tester.tap(control('Show more'));
      await tester.pumpAndSettle();
      expect(find.text('Three'), findsOneWidget);
      expect(control('Show more'), findsNothing);
      expect(toolkit.calls, contains('activity:b'));
    });

    testWidgets('an event that leaves the list closes its sheet', (
      tester,
    ) async {
      final toolkit = activity([_event('Morning brief', id: 'a')]);
      final h = await _open(tester, toolkit);
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Morning brief'));
      await tester.pumpAndSettle();
      expect(h.shell.popup.value, isA<ActivityOpen>());
      toolkit.activityEvents = [_event('Evening brief', id: 'b')];
      await h.toolkit.readActivity();
      await tester.pumpAndSettle();
      expect(h.shell.popup.value, isNull);
    });

    testWidgets('an event opens in a sheet that leads to its chat', (
      tester,
    ) async {
      final h = await _open(
        tester,
        activity([
          _event(
            'Morning brief',
            detail: 'Done. The answer is in the chat.',
            link: const ChatLink('q3', 'budget'),
          ),
        ]),
      );
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Morning brief'));
      await tester.pumpAndSettle();
      expect(find.text('This run'), findsOneWidget);
      expect(find.text('Done. The answer is in the chat.'), findsOneWidget);
      await tester.tap(control('Open the chat'));
      await tester.pumpAndSettle();
      expect(h.shell.toolkitPage, isNull);
      expect(h.chat.activeThread, 'budget');
    });

    testWidgets(
      'an event with a page opens it, and a file only says what it was',
      (tester) async {
        final h = await _open(
          tester,
          activity([
            _event(
              'Groceries',
              kind: ActivityKind.app,
              link: const PageLink('/apps-lean/g1.html'),
            ),
            _event(
              'Quote.pdf',
              kind: ActivityKind.file,
              detail: 'An 84 KB PDF.',
            ),
          ]),
          canViewApps: true,
        );
        await tester.tap(find.text('Activity'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Groceries'));
        await tester.pumpAndSettle();
        await tester.tap(control('Open it'));
        await tester.pumpAndSettle();
        expect(
          find.text('Web view of https://h:3001/apps-lean/g1.html?theme=light'),
          findsOneWidget,
        );
        h.shell.closePopup();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Quote.pdf'));
        await tester.pumpAndSettle();
        expect(find.text('An 84 KB PDF.'), findsOneWidget);
        expect(control('Open it'), findsNothing);
      },
    );

    testWidgets('a read the toolkit refuses says why', (tester) async {
      final toolkit = activity(const [])
        ..errors['activity'] = const ApiException('The toolkit is busy.');
      final h = await _open(tester, toolkit);
      h.shell.openToolkitPage(ToolkitPage.activity);
      await tester.pumpAndSettle();
      expect(find.text('Could not read the activity'), findsOneWidget);
      expect(find.text('The toolkit is busy.'), findsOneWidget);
    });

    testWidgets('a page of nothing says so', (tester) async {
      final h = await _open(tester, activity(const []));
      h.shell.openToolkitPage(ToolkitPage.activity);
      await tester.pumpAndSettle();
      expect(find.textContaining('Nothing yet.'), findsOneWidget);
      expect(find.byType(ActivityPage), findsOneWidget);
    });
  });
}
