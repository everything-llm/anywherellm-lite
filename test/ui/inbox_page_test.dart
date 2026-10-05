import 'package:flutter_test/flutter_test.dart';
import 'package:everything/core/ports.dart';
import 'package:everything/ui/state/nav_controller.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  testWidgets('says nothing is staged, and how to stage', (tester) async {
    await pumpApp(tester, route: const InboxRoute());
    expect(find.text('Inbox'), findsWidgets);
    expect(find.text('Nothing staged yet'), findsOneWidget);
    expect(
      find.text('Drop .md files here, or click to browse'),
      findsOneWidget,
    );
  });

  testWidgets('lists what is staged, read when the page opens', (tester) async {
    final api = FakeApi()..inboxValue = ['a.md', 'b.md'];
    await pumpApp(tester, api: api, route: const InboxRoute());
    expect(api.calls, contains('inbox'));
    expect(find.text('a.md'), findsOneWidget);
    expect(find.text('b.md'), findsOneWidget);
    expect(find.text('Staged'), findsOneWidget);
    expect(find.text('Nothing staged yet'), findsNothing);
  });

  testWidgets('says why the inbox could not be read', (tester) async {
    final api = FakeApi()
      ..errors['inbox'] = const ApiException('permission denied', status: 500);
    await pumpApp(tester, api: api, route: const InboxRoute());
    expect(find.text('Could not read the inbox'), findsOneWidget);
    expect(find.text('permission denied'), findsOneWidget);
  });

  testWidgets('is in the sidebar', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.text('Inbox').first);
    await tester.pumpAndSettle();
    expect(h.nav.route, const InboxRoute());
  });
}
