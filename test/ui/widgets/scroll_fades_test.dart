import 'package:anywherellm/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anywherellm/ui/widgets/scroll_fades.dart';

/// The fades' opacities, top first.
List<double> _fades(WidgetTester tester) => [
  for (final fade in tester.widgetList<AnimatedOpacity>(
    find.byType(AnimatedOpacity),
  ))
    fade.opacity,
];

void main() {
  testWidgets(
    'the bottom fades in while more lies below, the top once scrolled',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [Tokens.light]),
          home: SizedBox(
            height: 200,
            child: ScrollFades(
              child: ListView(
                children: [
                  for (var i = 0; i < 20; i++)
                    SizedBox(height: 50, child: Text('row $i')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_fades(tester), [0, 1]);
      await tester.drag(find.byType(ListView), const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(_fades(tester), [1, 1]);
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(_fades(tester), [1, 0]);
    },
  );

  testWidgets('a list that fits has no fades', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [Tokens.light]),
        home: ScrollFades(child: ListView(children: const [Text('one')])),
      ),
    );
    await tester.pumpAndSettle();
    expect(_fades(tester), [0, 0]);
  });
}
