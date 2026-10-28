import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anywherellm/ui/theme.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';

Tappable make({
  VoidCallback? onTap,
  bool? selected,
  bool? toggled,
  bool? expanded,
  String? tooltip,
}) => Tappable(
  label: 'Go',
  onTap: onTap,
  selected: selected,
  toggled: toggled,
  expanded: expanded,
  tooltip: tooltip,
  radius: BorderRadius.circular(8),
  color: Colors.white,
  child: const SizedBox(width: 60, height: 40, child: Text('inner')),
);

/// Builds [tappable] and hands its one semantics node to [check].
Future<void> checked(
  WidgetTester tester,
  Tappable tappable,
  void Function(SemanticsData data) check,
) async {
  final handle = tester.ensureSemantics();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Center(child: tappable),
    ),
  );
  check(find.semantics.byLabel('Go').evaluate().single.getSemanticsData());
  handle.dispose();
}

bool isOn(Tristate state) => state == Tristate.isTrue;

bool isReported(Tristate state) => state != Tristate.none;

void main() {
  testWidgets('reports a button with its label and hides the child text', (
    tester,
  ) async {
    await checked(tester, make(onTap: () {}), (data) {
      expect(data.label, 'Go');
      expect(data.flagsCollection.isButton, isTrue);
      expect(find.bySemanticsLabel('inner'), findsNothing);
    });
  });

  testWidgets('selected, toggled and expanded are reported when true', (
    tester,
  ) async {
    await checked(
      tester,
      make(onTap: () {}, selected: true, toggled: true, expanded: true),
      (data) {
        expect(isOn(data.flagsCollection.isSelected), isTrue);
        expect(isOn(data.flagsCollection.isToggled), isTrue);
        expect(isOn(data.flagsCollection.isExpanded), isTrue);
      },
    );
  });

  testWidgets('selected, toggled and expanded are reported when false', (
    tester,
  ) async {
    await checked(
      tester,
      make(onTap: () {}, selected: false, toggled: false, expanded: false),
      (data) {
        expect(isReported(data.flagsCollection.isSelected), isTrue);
        expect(isOn(data.flagsCollection.isSelected), isFalse);
        expect(isReported(data.flagsCollection.isToggled), isTrue);
        expect(isOn(data.flagsCollection.isToggled), isFalse);
        expect(isReported(data.flagsCollection.isExpanded), isTrue);
        expect(isOn(data.flagsCollection.isExpanded), isFalse);
      },
    );
  });

  testWidgets('a state left null is not reported at all', (tester) async {
    await checked(tester, make(onTap: () {}), (data) {
      expect(isReported(data.flagsCollection.isSelected), isFalse);
      expect(isReported(data.flagsCollection.isToggled), isFalse);
      expect(isReported(data.flagsCollection.isExpanded), isFalse);
    });
  });

  // House UI: disabled controls stay visible, drawn in opaque disabled colours, never faded.
  testWidgets('without onTap it is disabled, and never faded', (tester) async {
    await checked(tester, make(), (data) {
      expect(isReported(data.flagsCollection.isEnabled), isTrue);
      expect(isOn(data.flagsCollection.isEnabled), isFalse);
      expect(find.byType(Opacity), findsNothing);
    });
  });

  testWidgets('with onTap it is enabled and taps', (tester) async {
    var taps = 0;
    await checked(tester, make(onTap: () => taps++), (data) {
      expect(isOn(data.flagsCollection.isEnabled), isTrue);
    });
    await tester.tap(find.text('inner'));
    expect(taps, 1);
  });

  testWidgets('a tooltip is one node with the label, not a second label', (
    tester,
  ) async {
    await checked(tester, make(onTap: () {}, tooltip: 'Do the thing'), (data) {
      expect(data.label, 'Go');
      expect(data.tooltip, 'Do the thing');
    });
    expect(find.byTooltip('Do the thing'), findsOneWidget);
  });

  testWidgets('is a node of its own, not merged into the area that holds it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Semantics(
          label: 'Shelf',
          child: Align(
            alignment: Alignment.bottomLeft,
            child: make(onTap: () {}),
          ),
        ),
      ),
    );
    final node = find.semantics.byLabel('Go').evaluate().single;
    expect(node.label, 'Go');
    expect(node.rect.size, const Size(60, 40));
    handle.dispose();
  });

  testWidgets('the ink well is an ancestor of the child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Center(child: make(onTap: () {})),
      ),
    );
    expect(
      find.ancestor(of: find.text('inner'), matching: find.byType(InkWell)),
      findsOneWidget,
    );
  });
}
