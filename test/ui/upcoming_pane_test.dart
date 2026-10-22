import 'dart:ui';

import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:anywherellm/ui/sidebar.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/upcoming.dart';
import 'package:anywherellm/ui/upcoming_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_toolkit.dart';
import '../support/pump.dart';

const _desktop = Size(1440, 900);
const _split = Size(960, 600);
const _narrow = Size(800, 900);

/// A toolkit that lets jobs be changed, with two of them.
FakeToolkit _writable() => FakeToolkit()
  ..served = {
    ToolkitFeature.memories,
    ToolkitFeature.jobs,
    ToolkitFeature.jobsWrite,
  }
  ..jobs = const [
    ScheduledJob(
      id: '10',
      name: 'Morning brief',
      prompt: 'Give me today in four lines.',
      cron: '0 7 * * *',
      lastStatus: 'completed',
    ),
    ScheduledJob(
      id: '20',
      name: 'Price watch',
      prompt: 'Check the boiler service price.',
      cron: '0 */6 * * *',
    ),
  ];

/// The field whose hint is [hint].
Finder _field(String hint) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == hint,
);

Finder _inPane(Finder finder) =>
    find.descendant(of: find.byType(UpcomingPane), matching: finder);

Future<Harness> _open(
  WidgetTester tester,
  Size size, {
  FakeToolkit? toolkit,
}) async {
  final h = await pumpApp(
    tester,
    llm: planningServer(),
    toolkitServer: toolkit ?? _writable(),
    size: size,
  );
  await tester.pumpAndSettle();
  h.shell.openPane(Pane.upcoming);
  await tester.pumpAndSettle();
  return h;
}

bool _chosen(WidgetTester tester, String name) {
  final row = tester.getSemantics(
    _inPane(find.bySemanticsLabel(RegExp('^${RegExp.escape(name)},'))).first,
  );
  return row.flagsCollection.isSelected == Tristate.isTrue;
}

void main() {
  testWidgets('the sidebar opens Upcoming beside the first task', (
    tester,
  ) async {
    await pumpApp(
      tester,
      llm: planningServer(),
      toolkitServer: _writable(),
      size: _desktop,
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(Sidebar),
        matching: find.text('Upcoming'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UpcomingPane), findsOneWidget);
    expect(_inPane(find.text('Give me today in four lines.')), findsOneWidget);
    expect(_chosen(tester, 'Morning brief'), isTrue);
    expect(_inPane(find.text('New task')), findsOneWidget);

    await tester.tap(_inPane(find.text('Price watch')).first);
    await tester.pumpAndSettle();
    expect(
      _inPane(find.text('Check the boiler service price.')),
      findsOneWidget,
    );
    expect(_chosen(tester, 'Price watch'), isTrue);
  });

  testWidgets('the On switch turns the chosen task off', (tester) async {
    final toolkit = _writable();
    await _open(tester, _desktop, toolkit: toolkit);

    await tester.tap(control('Task on'));
    await tester.pumpAndSettle();

    expect(toolkit.jobs.first.enabled, isFalse);
  });

  testWidgets('Delete task asks over the window first', (tester) async {
    final toolkit = _writable();
    final h = await _open(tester, _desktop, toolkit: toolkit);

    await tester.tap(_inPane(find.text('Delete task')));
    await tester.pumpAndSettle();
    expect(h.shell.popup.value, const DeleteTask('10'));
    expect(
      find.text('Delete Morning brief? Its earlier runs go with it.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(toolkit.jobs, hasLength(2));

    await tester.tap(_inPane(find.text('Delete task')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(toolkit.jobs.map((j) => j.name), ['Price watch']);
    expect(h.shell.popup.value, isNull);
    expect(_chosen(tester, 'Price watch'), isTrue);
  });

  testWidgets('Edit and New task show their form in place of the task', (
    tester,
  ) async {
    final toolkit = _writable();
    await _open(tester, _desktop, toolkit: toolkit);

    await tester.tap(_inPane(find.text('Edit')));
    await tester.pumpAndSettle();
    expect(_inPane(find.text('Edit task')), findsOneWidget);
    await tester.tap(_inPane(find.text('Cancel')));
    await tester.pumpAndSettle();
    expect(_inPane(find.text('Run now')), findsOneWidget);

    await tester.tap(_inPane(find.text('New task')));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Morning brief'), 'Bins');
    await tester.enterText(
      _field('Summarise today: the weather, the bins, anything due.'),
      'Say which bins go out.',
    );
    await tester.tap(_inPane(find.text('Save')));
    await tester.pumpAndSettle();
    expect(toolkit.jobs.map((j) => j.name), contains('Bins'));
    expect(_inPane(find.text('Run now')), findsOneWidget);
  });

  testWidgets('a toolkit that only lists jobs fills the page with them', (
    tester,
  ) async {
    final toolkit = _writable()
      ..served = {ToolkitFeature.memories, ToolkitFeature.jobs};
    await _open(tester, _desktop, toolkit: toolkit);

    expect(_inPane(find.text('Morning brief')), findsOneWidget);
    expect(_inPane(find.text('Run now')), findsNothing);
    expect(_inPane(find.text('New task')), findsNothing);
    expect(_inPane(find.textContaining('Read only here.')), findsOneWidget);
  });

  testWidgets('narrower, it is Settings\' Upcoming page', (tester) async {
    await _open(tester, _narrow);

    expect(_inPane(find.byType(UpcomingPage)), findsOneWidget);
    await tester.tap(_inPane(find.text('Morning brief')));
    await tester.pumpAndSettle();
    expect(find.text('Give me today in four lines.'), findsOneWidget);
  });

  for (final (size, scale) in [
    (_desktop, 1.0),
    (_split, 1.0),
    (_narrow, 1.0),
    (_split, 2.0),
  ]) {
    testWidgets(
      'the pane fits at ${size.width.toInt()}x${size.height.toInt()}, '
      '${(scale * 100).toInt()}% text',
      (tester) async {
        final dispatcher = tester.platformDispatcher;
        dispatcher.textScaleFactorTestValue = scale;
        addTearDown(dispatcher.clearTextScaleFactorTestValue);
        await _open(tester, size);
        expect(tester.takeException(), isNull);
        if (size == _narrow) return;

        await tester.tap(_inPane(find.text('New task')).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
