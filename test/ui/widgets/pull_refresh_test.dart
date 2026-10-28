import 'package:anywherellm/ui/tokens.dart';
import 'package:anywherellm/ui/widgets/pull_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A refresh under way, with the platform's animations on or off.
Widget _refreshing({required bool still}) => MaterialApp(
  theme: ThemeData(extensions: [Tokens.light]),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: still),
    child: PullRefresh(
      onRefresh: () {},
      refreshing: true,
      child: ListView(
        reverse: true,
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [Text('turn')],
      ),
    ),
  ),
);

void main() {
  testWidgets('the refresh icon turns while it refreshes', (tester) async {
    await tester.pumpWidget(_refreshing(still: false));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.hasRunningAnimations, isTrue);
  });

  // House UI removes spin under reduced motion; the icon still shows it refreshes.
  testWidgets('with animations off the icon shows, still', (tester) async {
    await tester.pumpWidget(_refreshing(still: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byType(RotationTransition), findsOneWidget);
    expect(
      tester.widget<RotationTransition>(find.byType(RotationTransition)).turns,
      isA<AlwaysStoppedAnimation<double>>(),
    );
  });
}
