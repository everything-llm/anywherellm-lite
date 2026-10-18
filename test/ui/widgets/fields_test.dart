import 'package:anywherellm/ui/theme.dart';
import 'package:anywherellm/ui/widgets/fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
