import 'package:anywherellm/ui/icons.dart';
import 'package:anywherellm/ui/theme.dart';
import 'package:anywherellm/ui/widgets/controls.dart';
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
      AppSwitch(
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
    await tester.tap(find.byType(AppSwitch));
    expect(changed, isFalse);
  });

  testWidgets('a badge shows its text', (tester) async {
    await show(tester, const AppBadge('Set', kind: BadgeKind.ok));
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
      Wrap(children: [for (final name in names) AppIcon(name)]),
    );
    expect(find.byType(AppIcon), findsNWidgets(names.length));
    expect(tester.takeException(), isNull);
  });
}
