import 'package:anywherellm/core/created.dart';
import 'package:anywherellm/ui/artifacts.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

const phone = Size(390, 844);

final _working = CreatedFile(
  id: 'threads/12/quotes.csv',
  name: 'quotes.csv',
  dir: '',
  size: 3000,
  modified: DateTime.now().subtract(const Duration(hours: 1)),
  area: CreatedArea.work,
  expires: DateTime.now().add(const Duration(days: 4, hours: 12)),
);

final _page = CreatedFile(
  id: 'public/costs/index.html',
  name: 'index.html',
  dir: 'costs',
  size: 900,
  modified: DateTime.now().subtract(const Duration(days: 1)),
  area: CreatedArea.public,
  url: 'https://host.example.ts.net:8447/q3/costs/index.html',
);

final _kept = CreatedFile(
  id: 'project/report.pdf',
  name: 'report.pdf',
  dir: '',
  size: 96000,
  modified: DateTime.now().subtract(const Duration(minutes: 5)),
  area: CreatedArea.project,
);

final _groceries = CreatedApp(
  id: 'apps/groceries',
  name: 'groceries',
  title: 'Groceries',
  kind: 'list',
  summary: '4 of 6 left',
  modified: DateTime.now(),
  page: Uri.parse('https://host.example.ts.net:8447/q3/apps/groceries/'),
  card: Uri.parse(
    'https://host.example.ts.net:8445/_live/apps/q3/groceries.png',
  ),
  link: Uri.parse('https://host.example.ts.net:8445/_live/apps/q3/groceries'),
);

/// A phone over a server whose open workspace holds [files], and [apps] when its host lists
/// them.
Future<Harness> _phone(
  WidgetTester tester,
  List<CreatedFile> files, {
  List<CreatedApp>? apps,
}) async {
  final llm = planningServer();
  final h = await pumpApp(tester, llm: llm, size: phone);
  llm.created[h.chat.activeSlug!] = CreatedList(
    files: files,
    apps: apps,
    used: 1200 * 1024 * 1024,
    warn: 4 * 1024 * 1024 * 1024,
    limit: 5 * 1024 * 1024 * 1024,
  );
  return h;
}

Finder _page$() => find.byType(ArtifactsPage);

Finder inPage(Finder finder) => find.descendant(of: _page$(), matching: finder);

Future<void> _openSheet(WidgetTester tester, String name) async {
  await tester.tap(inPage(find.text(name)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the drawer counts the created files and opens Artifacts', (
    tester,
  ) async {
    final h = await _phone(tester, [_kept, _page, _working]);
    h.shell.toggleSide();
    await tester.pumpAndSettle();
    expect(control('Artifacts, 3 files'), findsOneWidget);
    await tester.tap(control('Artifacts, 3 files'));
    await tester.pumpAndSettle();
    expect(h.shell.sideOpen, isFalse);
    expect(_page$(), findsOneWidget);
    expect(inPage(find.text('3 files')), findsOneWidget);
    expect(inPage(find.text('1.2 GB of 5.0 GB')), findsOneWidget);
    expect(inPage(find.text('report.pdf')), findsOneWidget);
    expect(inPage(find.textContaining('Goes in 5 days')), findsOneWidget);
    expect(inPage(find.textContaining('On the web')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.shell.phonePage, isNull);
  });

  testWidgets('a file\'s sheet offers only what fits it', (tester) async {
    final h = await _phone(tester, [_kept, _page, _working]);
    h.shell.openPhonePage(PhonePage.artifacts);
    await tester.pumpAndSettle();
    await _openSheet(tester, 'report.pdf');
    expect(find.byType(CreatedSheet), findsOneWidget);
    expect(control('Download'), findsOneWidget);
    expect(control('Open page'), findsNothing);
    expect(control('Keep'), findsNothing);
    expect(control('Delete file'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CreatedSheet), findsNothing);
    expect(_page$(), findsOneWidget);

    await _openSheet(tester, 'index.html');
    await tester.tap(control('Open page'));
    await tester.pumpAndSettle();
    expect(h.opened.single.toString(), _page.url);
  });

  testWidgets('Download saves the file under its name', (tester) async {
    final h = await _phone(tester, [_kept]);
    h.llm.createdBytes[_kept.id] = [1, 2, 3];
    h.shell.openPhonePage(PhonePage.artifacts);
    await tester.pumpAndSettle();
    await _openSheet(tester, 'report.pdf');
    await tester.tap(control('Download'));
    await tester.pumpAndSettle();
    expect(h.saved['report.pdf'], [1, 2, 3]);
  });

  testWidgets('Keep moves a working file into the project', (tester) async {
    final h = await _phone(tester, [_working]);
    h.shell.openPhonePage(PhonePage.artifacts);
    await tester.pumpAndSettle();
    await _openSheet(tester, 'quotes.csv');
    await tester.tap(control('Keep'));
    await tester.pumpAndSettle();
    expect(h.llm.calls, contains('keepCreated:${_working.id}'));
    expect(inPage(find.textContaining('Goes in')), findsNothing);
  });

  testWidgets('Delete file asks first, and Keep leaves it', (tester) async {
    final h = await _phone(tester, [_kept]);
    h.shell.openPhonePage(PhonePage.artifacts);
    await tester.pumpAndSettle();
    await _openSheet(tester, 'report.pdf');
    await tester.tap(control('Delete file'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Delete report.pdf from the workspace?'),
      findsOneWidget,
    );
    await tester.tap(control('Keep'));
    await tester.pumpAndSettle();
    expect(h.llm.calls, isNot(contains('deleteCreated:${_kept.id}')));
    await _openSheet(tester, 'report.pdf');
    await tester.tap(control('Delete file'));
    await tester.pumpAndSettle();
    await tester.tap(control('Delete'));
    await tester.pumpAndSettle();
    expect(h.llm.calls, contains('deleteCreated:${_kept.id}'));
    expect(inPage(find.text('report.pdf')), findsNothing);
    expect(inPage(find.text('No created files yet.')), findsOneWidget);
  });

  testWidgets('a server that does not list them has no Artifacts', (
    tester,
  ) async {
    final h = await _phone(tester, const []);
    h.llm.noCreatedRoute = true;
    h.shell.toggleSide();
    await tester.pumpAndSettle();
    expect(control('Artifacts'), findsNothing);
    expect(find.text('Artifacts'), findsNothing);
  });

  testWidgets(
    'apps come first, counted with the files, and open as in a chat',
    (tester) async {
      final h = await _phone(tester, [_kept], apps: [_groceries]);
      h.shell.toggleSide();
      await tester.pumpAndSettle();
      expect(control('Artifacts, 1 app · 1 file'), findsOneWidget);
      await tester.tap(control('Artifacts, 1 app · 1 file'));
      await tester.pumpAndSettle();
      expect(inPage(find.text('1 app · 1 file')), findsOneWidget);
      expect(inPage(find.text('List · 4 of 6 left')), findsOneWidget);
      await tester.tap(inPage(find.text('Groceries')));
      await tester.pumpAndSettle();
      expect(h.shell.phonePage, isNull);
      expect(h.shell.app?.name, 'Groceries');
      expect(h.shell.app?.page, _groceries.link);
    },
  );

  testWidgets('an app\'s sheet opens it in the browser or deletes it', (
    tester,
  ) async {
    final h = await _phone(tester, const [], apps: [_groceries]);
    h.shell.openPhonePage(PhonePage.artifacts);
    await tester.pumpAndSettle();
    await tester.tap(control('Open in the browser or delete Groceries'));
    await tester.pumpAndSettle();
    expect(control('Open'), findsOneWidget);
    await tester.tap(control('Open in the browser'));
    await tester.pumpAndSettle();
    expect(h.opened.single, _groceries.page);

    await tester.tap(control('Open in the browser or delete Groceries'));
    await tester.pumpAndSettle();
    await tester.tap(control('Delete app'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Its data goes with it'), findsOneWidget);
    await tester.tap(control('Delete'));
    await tester.pumpAndSettle();
    expect(h.llm.calls, contains('deleteCreated:apps/groceries'));
    expect(inPage(find.text('No apps in this workspace yet.')), findsOneWidget);
  });

  testWidgets('a host that does not list apps shows no Apps', (tester) async {
    final h = await _phone(tester, [_kept]);
    h.shell.openPhonePage(PhonePage.artifacts);
    await tester.pumpAndSettle();
    expect(inPage(find.text('APPS')), findsNothing);
    expect(inPage(find.text('1 file')), findsOneWidget);
  });
}
