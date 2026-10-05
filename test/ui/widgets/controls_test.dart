import 'package:everything/ui/icons.dart';
import 'package:everything/ui/theme.dart';
import 'package:everything/ui/widgets/controls.dart';
import 'package:flutter/material.dart';

import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';

Future<void> show(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: buildTheme(Brightness.light),
    home: Scaffold(
      body: Center(child: SizedBox(width: 300, child: child)),
    ),
  ),
);

void main() {
  testWidgets('a switch reports its state and flips when tapped', (
    tester,
  ) async {
    bool? changed;
    await show(
      tester,
      NilsSwitch(
        value: true,
        label: 'Use a.md in answers',
        onChanged: (v) => changed = v,
      ),
    );
    final data = find.semantics
        .byLabel('Use a.md in answers')
        .evaluate()
        .single
        .getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isToggled, Tristate.isTrue);
    await tester.tap(find.byType(NilsSwitch));
    expect(changed, isFalse);
  });

  testWidgets('a badge shows its text', (tester) async {
    await show(tester, const NilsBadge('Set', kind: BadgeKind.ok));
    expect(find.text('Set'), findsOneWidget);
  });

  testWidgets('every icon draws, on either box', (tester) async {
    const names = [
      'chat',
      'settings',
      'plus',
      'pencil',
      'trash',
      'close',
      'doc',
      'send',
      'hamburger',
    ];
    await show(
      tester,
      Wrap(children: [for (final name in names) NilsIcon(name)]),
    );
    expect(find.byType(NilsIcon), findsNWidgets(names.length));
    expect(tester.takeException(), isNull);
  });
}
