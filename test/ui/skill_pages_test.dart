import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/skill_pages.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:anywherellm/ui/state/chat_controller.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_toolkit.dart';
import '../support/pump.dart';

const _vault = '/vault-lean/aB3_-x9.html';
const _newVault = '/vault-lean/zZ8_-q2.html';
const _library = '/library-lean/q9Zx_-1aB2.html';

FakeToolkit _toolkit({
  Set<String> extra = const {ToolkitFeature.pages},
  SkillPages pages = const SkillPages(vault: _vault),
}) => FakeToolkit()
  ..served = {ToolkitFeature.memories, ToolkitFeature.jobs, ...extra}
  ..skillPages = pages;

Future<Harness> _open(WidgetTester tester, FakeToolkit toolkit) => pumpApp(
  tester,
  llm: planningServer(),
  toolkitServer: toolkit,
  shelf: true,
  canViewApps: true,
);

int _reads(FakeToolkit toolkit) =>
    toolkit.calls.where((call) => call == 'pages').length;

void main() {
  testWidgets('the card shows the pages that are set up and no other', (
    tester,
  ) async {
    final toolkit = _toolkit();
    final h = await _open(tester, toolkit);
    expect(find.text('Vault'), findsOneWidget);
    expect(find.text('Keys, sign-ins and allowed addresses'), findsOneWidget);
    expect(find.text('Library'), findsNothing);
    expect(h.toolkit.pagesFound, {SkillPage.vault});
  });

  testWidgets('a tap reads where the page is afresh and opens that one', (
    tester,
  ) async {
    final toolkit = _toolkit();
    final h = await _open(tester, toolkit);
    final before = _reads(toolkit);
    expect(before, greaterThanOrEqualTo(1));
    toolkit.skillPages = const SkillPages(vault: _newVault);
    await tester.tap(find.text('Vault'));
    await tester.pumpAndSettle();
    expect(_reads(toolkit), before + 1);
    expect(
      (h.shell.popup.value as PageOpen).page,
      Uri.parse('https://h:3001$_newVault?theme=light'),
    );
    expect(h.shell.shelfOpen, isFalse);
    expect(h.chat.linkNotice, isNull);
  });

  testWidgets('the Library opens as it is, without a theme', (tester) async {
    final toolkit = _toolkit(
      pages: const SkillPages(library: _library, vault: _vault),
    );
    final h = await _open(tester, toolkit);
    expect(find.text('Toolkits and runs'), findsOneWidget);
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(
      (h.shell.popup.value as PageOpen).page,
      Uri.parse('https://h:3001$_library'),
    );
    expect(h.shell.shelfOpen, isFalse);
  });

  testWidgets('a tap that finds the page gone says so and hides its row', (
    tester,
  ) async {
    final toolkit = _toolkit();
    final h = await _open(tester, toolkit);
    toolkit.skillPages = const SkillPages();
    await tester.tap(find.text('Vault'));
    await tester.pump();
    await tester.pump();
    expect(h.shell.popup.value, isNull);
    expect(h.chat.linkNotice?.title, 'The Vault is not set up yet');
    expect(h.chat.linkNotice?.text, contains('Ask the agent'));
    expect(h.shell.shelfOpen, isFalse);
    expect(h.toolkit.pagesFound, isEmpty);
    await tester.pump(ChatController.linkNoticeFor);
    await tester.pumpAndSettle();
  });

  testWidgets('a read that fails on the tap says why, without the path', (
    tester,
  ) async {
    final toolkit = _toolkit();
    final h = await _open(tester, toolkit);
    toolkit.errors['pages'] = const ApiException('The bridge is down.');
    await tester.tap(find.text('Vault'));
    await tester.pump();
    await tester.pump();
    expect(h.chat.linkNotice?.title, 'Could not open the Vault');
    expect(h.chat.linkNotice?.text, 'The bridge is down.');
    expect(h.shell.popup.value, isNull);
    expect(h.shell.shelfOpen, isFalse);
    // Not a refusal of the key: the page is still set up.
    expect(h.toolkit.pagesFound, {SkillPage.vault});
    await tester.pump(ChatController.linkNoticeFor);
    await tester.pumpAndSettle();
  });

  testWidgets('a key the bridge refuses shows no rows and no notice', (
    tester,
  ) async {
    for (final status in [401, 403]) {
      final toolkit = _toolkit();
      toolkit.errors['pages'] = ApiException('No.', status: status);
      final h = await _open(tester, toolkit);
      expect(find.text('Vault'), findsNothing, reason: '$status');
      expect(find.text('Library'), findsNothing, reason: '$status');
      expect(h.chat.linkNotice, isNull, reason: '$status');
      expect(h.toolkit.pagesFound, isEmpty, reason: '$status');
    }
  });

  testWidgets('a refusal on the tap hides the rows and tells the person', (
    tester,
  ) async {
    final toolkit = _toolkit();
    final h = await _open(tester, toolkit);
    toolkit.errors['pages'] = const ApiException('No.', status: 403);
    await tester.tap(find.text('Vault'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Vault'), findsNothing);
    expect(h.chat.linkNotice?.title, 'Could not open the Vault');
    await tester.pump(ChatController.linkNoticeFor);
    await tester.pumpAndSettle();
  });

  testWidgets('a toolkit that does not serve pages shows none and asks none', (
    tester,
  ) async {
    final toolkit = _toolkit(extra: const {});
    final h = await _open(tester, toolkit);
    expect(find.text('Vault'), findsNothing);
    expect(find.text('Library'), findsNothing);
    expect(toolkit.calls, isNot(contains('pages')));
    expect(h.toolkit.pagesFound, isEmpty);
  });

  testWidgets('another server forgets which pages were found', (tester) async {
    final toolkit = _toolkit();
    final h = await _open(tester, toolkit);
    expect(h.toolkit.pagesFound, {SkillPage.vault});
    toolkit.skillPages = const SkillPages(library: _library);
    await h.settings.save('https://other:3001', 'K2');
    await tester.pumpAndSettle();
    // The new server's card reads afresh; nothing of the old one's remains.
    expect(h.toolkit.pagesFound, {SkillPage.library});
    expect(find.text('Vault'), findsNothing);
    expect(find.text('Library'), findsOneWidget);
  });
}
