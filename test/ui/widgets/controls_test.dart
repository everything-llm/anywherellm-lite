import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything/ui/icons.dart';
import 'package:everything/ui/theme.dart';
import 'package:everything/ui/widgets/basics.dart';
import 'package:everything/ui/widgets/fields.dart';
import 'package:everything/ui/widgets/select.dart';

Future<void> show(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: buildTheme(Brightness.light),
    home: Scaffold(
      body: Center(child: SizedBox(width: 300, child: child)),
    ),
  ),
);

void main() {
  testWidgets('a search field reports what is typed and shows its hint', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final typed = <String>[];
    await show(
      tester,
      SearchField(
        controller: controller,
        hint: 'Search research',
        onChanged: typed.add,
      ),
    );
    expect(find.text('Search research'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'maps');
    expect(typed, ['maps']);
    expect(find.byType(NilsIcon), findsOneWidget);
  });

  testWidgets('a select shows the current choice and changes it from a menu', (
    tester,
  ) async {
    final picked = <String>[];
    await show(
      tester,
      NilsSelect(
        label: 'Filter by type',
        value: '',
        options: const [
          (value: '', label: 'All types'),
          (value: 'report', label: 'report (2)'),
        ],
        onChanged: picked.add,
      ),
    );
    expect(find.text('All types'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(NilsSelect)).label,
      'Filter by type, All types',
    );
    await tester.tap(find.byType(NilsSelect));
    await tester.pumpAndSettle();
    await tester.tap(find.text('report (2)'));
    await tester.pumpAndSettle();
    expect(picked, ['report']);
  });

  testWidgets('a select with an unknown value shows its first option', (
    tester,
  ) async {
    await show(
      tester,
      NilsSelect(
        label: 'Filter',
        value: 'gone',
        options: const [(value: '', label: 'All')],
        onChanged: (_) {},
      ),
    );
    expect(find.text('All'), findsOneWidget);
  });

  testWidgets('a mono page head sets a name that is code in the mono face', (
    tester,
  ) async {
    await show(tester, const PageHead('commit', mono: true));
    final style = tester.widget<Text>(find.text('commit')).style!;
    expect(style.fontFamily, 'JetBrains Mono');
    expect(style.fontSize, 28);
  });

  testWidgets('every new icon draws', (tester) async {
    await show(
      tester,
      Row(
        children: [
          for (final name in ['folder', 'search']) NilsIcon(name),
        ],
      ),
    );
    expect(find.byType(NilsIcon), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
