import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/state/chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

void main() {
  const title = 'Can’t reach your AnythingLLM';

  testWidgets('a server that cannot be reached has a banner under the header', (
    tester,
  ) async {
    final llm = planningServer()
      ..errors['workspaces'] = const ApiException('Down');
    await pumpApp(tester, llm: llm);
    expect(find.text(title), findsOneWidget);
    expect(find.textContaining('same network'), findsOneWidget);
    expect(find.text('https://h:3001'), findsOneWidget);
    // The banner says it, so the read's own failure is not shown a second time.
    expect(find.text('Could not read the workspaces'), findsNothing);
    // The message box stays open.
    expect(composerField, findsOneWidget);
    // Nothing was read, so no empty state claims there are no workspaces.
    expect(find.text('Make a workspace to start asking'), findsNothing);
  });

  testWidgets('a later failure shows under the banner', (tester) async {
    final llm = planningServer()
      ..errors['workspaces'] = const ApiException('Down')
      ..errors['createWorkspace'] = const ApiException('Refused');
    final h = await pumpApp(tester, llm: llm);
    await h.chat.createWorkspace('Trips');
    await tester.pump();
    expect(find.text(title), findsOneWidget);
    expect(find.text('Could not make the workspace'), findsOneWidget);
  });

  testWidgets('Try again reads the workspaces at once and clears the banner', (
    tester,
  ) async {
    final llm = planningServer()
      ..errors['workspaces'] = const ApiException('Down');
    await pumpApp(tester, llm: llm);
    llm.errors.remove('workspaces');
    final before = llm.calls.where((c) => c == 'workspaces').length;
    await tester.tap(control('Try again'));
    await tester.pumpAndSettle();
    expect(llm.calls.where((c) => c == 'workspaces').length, before + 1);
    expect(find.text(title), findsNothing);
  });

  testWidgets('the banner clears itself once the server answers', (
    tester,
  ) async {
    final llm = planningServer()
      ..errors['workspaces'] = const ApiException('Down');
    await pumpApp(tester, llm: llm);
    int reads() => llm.calls.where((c) => c == 'workspaces').length;
    final before = reads();
    await tester.pump(ChatController.retryEvery);
    await tester.pump();
    // Read again, and still down.
    expect(reads(), before + 1);
    expect(find.text(title), findsOneWidget);

    llm.errors.remove('workspaces');
    await tester.pump(ChatController.retryEvery);
    await tester.pumpAndSettle();
    expect(find.text(title), findsNothing);
    expect(find.text('No workspaces yet'), findsNothing);
    // Once it answers, nothing more is read for the banner.
    final after = reads();
    await tester.pump(ChatController.retryEvery * 2);
    expect(reads(), after);
  });

  testWidgets('Connection opens the address and key', (tester) async {
    final llm = planningServer()
      ..errors['workspaces'] = const ApiException('Down');
    final h = await pumpApp(tester, llm: llm);
    await tester.tap(control('Connection'));
    await tester.pumpAndSettle();
    expect(h.shell.settingsPage, SettingsPage.connection);
  });

  testWidgets('a server that answers has no banner', (tester) async {
    await pumpApp(tester, llm: planningServer());
    expect(find.text(title), findsNothing);
  });
}
