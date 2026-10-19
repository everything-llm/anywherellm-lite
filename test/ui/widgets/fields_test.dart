import 'package:anywherellm/ui/theme.dart';
import 'package:anywherellm/ui/widgets/fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  focusRingTests();

  testWidgets('a named field is one node with its name, not a name beside it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Material(
          child: Semantics(
            label: 'Page',
            child: const Align(
              child: SizedBox(
                width: 200,
                child: FieldName(
                  label: 'Name',
                  child: TextField(
                    decoration: InputDecoration(hintText: 'Groceries'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final named = find.semantics.byLabel(RegExp('Name'));
    expect(named.evaluate(), hasLength(1));
    final data = named.evaluate().single.getSemanticsData();
    expect(data.flagsCollection.isTextField, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.label, isNot(contains('Page')));
    handle.dispose();
  });
}

/// Whether a [FocusRing] is drawing its ring now.
bool _ringShows(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(FocusRing),
        matching: find.byType(DecoratedBox),
      ),
    )
    .any(
      (box) =>
          box.position == DecorationPosition.foreground &&
          (box.decoration as BoxDecoration).border != null,
    );

void focusRingTests() {
  testWidgets('the focus ring shows for a keyboard, not for a touch', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: FocusRing(
            focus: focus,
            child: TextField(focusNode: focus),
          ),
        ),
      ),
    );
    expect(_ringShows(tester), isFalse);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    expect(_ringShows(tester), isFalse);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await tester.pump();
    expect(_ringShows(tester), isTrue);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });
}
