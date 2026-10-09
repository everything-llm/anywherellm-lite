import 'package:anywherellm/core/created.dart';
import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/ui/files/essentials.dart';
import 'package:anywherellm/ui/files/file_tree.dart';
import 'package:anywherellm/ui/files/files_view.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/widgets/confirm_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

Finder inPane(Finder finder) =>
    find.descendant(of: find.byType(FilesView), matching: finder);

CreatedFile _file(
  String id, {
  CreatedArea area = CreatedArea.project,
  Duration age = const Duration(hours: 2),
  Duration? goes,
  String? url,
  int size = 5,
}) {
  final steps = id.split('/');
  final rest = area == CreatedArea.work ? steps.skip(2) : steps.skip(1);
  return CreatedFile(
    id: id,
    name: steps.last,
    dir: rest.length > 1 ? rest.take(rest.length - 1).join('/') : '',
    size: size,
    modified: DateTime.now().subtract(age),
    area: area,
    expires: goes == null ? null : DateTime.now().add(goes),
    url: url,
  );
}

CreatedList _list(List<CreatedFile> files, {int used = 32379}) => CreatedList(
  files: files,
  used: used,
  warn: 4 * 1024 * 1024 * 1024,
  limit: 5 * 1024 * 1024 * 1024,
);

/// Files opened on Created files, with the open workspace's files as [files].
Future<Harness> openCreated(
  WidgetTester tester,
  List<CreatedFile> files, {
  FakeAnythingLlm? llm,
  CreatedList? list,
}) async {
  final server = llm ?? planningServer();
  final h = await pumpApp(tester, llm: server, size: const Size(1280, 1800));
  server.created[h.chat.activeSlug!] = list ?? _list(files);
  h.shell.showPane(Pane.files);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(FileTree),
      matching: control('Created files'),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

void main() {
  final threeDays = const Duration(days: 2, hours: 12);

  testWidgets('lists the files newest first, marking only those that differ', (
    tester,
  ) async {
    final h = await openCreated(tester, [
      _file(
        'threads/12/scratch/out.txt',
        area: CreatedArea.work,
        age: const Duration(minutes: 5),
        goes: threeDays,
      ),
      _file('project/report.pdf', age: const Duration(days: 3)),
      _file(
        'public/site/index.html',
        area: CreatedArea.public,
        url: 'https://host.example.ts.net:8447/q3/site/index.html',
        age: const Duration(hours: 5),
      ),
      _file('shared/notes.md', area: CreatedArea.shared),
    ]);
    expect(h.llm.calls, contains('createdFiles:${h.chat.activeSlug}'));
    expect(inPane(find.text('4 files')), findsOneWidget);
    expect(inPane(find.text('out.txt')), findsOneWidget);
    expect(inPane(find.text('Goes in 3 days')), findsOneWidget);
    expect(inPane(find.text('On the web')), findsOneWidget);
    expect(inPane(find.text('Other workspaces can read')), findsOneWidget);
    // A kept file carries no mark of its own.
    expect(inPane(find.text('report.pdf')), findsOneWidget);
    expect(inPane(find.textContaining('3 days ago')), findsOneWidget);
    expect(inPane(find.text('scratch · 5 B · 5 min ago')), findsOneWidget);
    expect(inPane(find.text('31.6 KB of 5.0 GB used')), findsOneWidget);
  });

  testWidgets('says so when the room is nearly full', (tester) async {
    await openCreated(
      tester,
      const [],
      list: _list(const [], used: 4500 * 1024 * 1024),
    );
    expect(inPane(find.text('No files yet.')), findsOneWidget);
    expect(inPane(find.textContaining('Nearly full.')), findsOneWidget);
  });

  testWidgets('Download saves the file under its name', (tester) async {
    final file = _file('project/report.pdf');
    final h = await openCreated(tester, [file]);
    h.llm.createdBytes[file.id] = [1, 2, 3];
    await tester.tap(inPane(control('Download report.pdf')));
    await tester.pumpAndSettle();
    expect(h.saved['report.pdf'], [1, 2, 3]);
    expect(h.llm.calls, contains('downloadCreated:project/report.pdf'));
  });

  testWidgets('a download the server refuses shows why, and saves nothing', (
    tester,
  ) async {
    final file = _file('project/report.pdf');
    final h = await openCreated(tester, [file]);
    h.llm.errors['downloadCreated'] = const ApiException(
      '\'report.pdf\' is over 64 MB, too big to send here',
      status: 413,
    );
    await tester.tap(inPane(control('Download report.pdf')));
    await tester.pumpAndSettle();
    expect(h.saved, isEmpty);
    expect(inPane(find.text('Could not get report.pdf')), findsOneWidget);
    expect(inPane(find.textContaining('too big to send here')), findsOneWidget);
  });

  testWidgets('Keep moves a working file into the project and drops its mark', (
    tester,
  ) async {
    final h = await openCreated(tester, [
      _file(
        'threads/12/scratch/out.txt',
        area: CreatedArea.work,
        goes: threeDays,
      ),
    ]);
    expect(inPane(control('Keep out.txt')), findsOneWidget);
    await tester.tap(inPane(control('Keep out.txt')));
    await tester.pumpAndSettle();
    expect(h.llm.calls, contains('keepCreated:threads/12/scratch/out.txt'));
    expect(inPane(find.text('Goes in 3 days')), findsNothing);
    expect(inPane(find.text('out.txt')), findsOneWidget);
    // A kept file has nothing to keep.
    expect(inPane(control('Keep out.txt')), findsNothing);
    expect(h.created.list!.files.single.id, 'project/scratch/out.txt');
  });

  testWidgets('Keep that the server refuses leaves the file and says why', (
    tester,
  ) async {
    final h = await openCreated(tester, [
      _file('threads/12/out.txt', area: CreatedArea.work, goes: threeDays),
      _file('project/out.txt'),
    ]);
    await tester.tap(inPane(control('Keep out.txt').first));
    await tester.pumpAndSettle();
    expect(inPane(find.text('Could not keep out.txt')), findsOneWidget);
    expect(inPane(find.textContaining('already has')), findsOneWidget);
    expect(h.created.list!.files, hasLength(2));
  });

  testWidgets('a file that is kept or on the web has no Keep', (tester) async {
    await openCreated(tester, [
      _file('project/report.pdf'),
      _file('shared/notes.md', area: CreatedArea.shared),
    ]);
    expect(inPane(control('Keep report.pdf')), findsNothing);
    expect(inPane(control('Keep notes.md')), findsNothing);
  });

  testWidgets('Delete asks once more, and Cancel keeps the file', (
    tester,
  ) async {
    final h = await openCreated(tester, [_file('project/report.pdf')]);
    await tester.tap(inPane(control('Delete report.pdf')));
    await tester.pumpAndSettle();
    expect(
      inPane(find.textContaining('Delete report.pdf from the workspace?')),
      findsOneWidget,
    );
    expect(h.llm.calls, isNot(contains('deleteCreated:project/report.pdf')));
    await tester.tap(inPane(find.text('Cancel')));
    await tester.pumpAndSettle();
    expect(inPane(find.textContaining('from the workspace?')), findsNothing);
    expect(inPane(find.text('report.pdf')), findsOneWidget);
    expect(h.llm.calls.where((c) => c.startsWith('deleteCreated')), isEmpty);
  });

  testWidgets('Delete, once confirmed, removes the file', (tester) async {
    final h = await openCreated(tester, [
      _file('project/report.pdf'),
      _file('project/other.txt'),
    ]);
    await tester.tap(inPane(control('Delete report.pdf')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ConfirmBox),
        matching: find.text('Delete'),
      ),
    );
    await tester.pumpAndSettle();
    expect(h.llm.calls, contains('deleteCreated:project/report.pdf'));
    expect(inPane(find.text('report.pdf')), findsNothing);
    expect(inPane(find.text('other.txt')), findsOneWidget);
    expect(inPane(find.text('1 file')), findsOneWidget);
  });

  testWidgets('Open page opens a page on the web, and only a page', (
    tester,
  ) async {
    final h = await openCreated(tester, [
      _file(
        'public/site/index.html',
        area: CreatedArea.public,
        url: 'https://host.example.ts.net:8447/q3/site/index.html',
      ),
      _file(
        'public/data.json',
        area: CreatedArea.public,
        url: 'https://host.example.ts.net:8447/q3/data.json',
      ),
    ]);
    expect(inPane(control('Open page data.json')), findsNothing);
    await tester.tap(inPane(control('Open page index.html')));
    await tester.pumpAndSettle();
    expect(h.opened.map((u) => u.toString()), [
      'https://host.example.ts.net:8447/q3/site/index.html',
    ]);
  });

  testWidgets(
    'says where an answer\'s files are when the server cannot list them',
    (tester) async {
      final llm = planningServer()..noCreatedRoute = true;
      final h = await openCreated(tester, const [], llm: llm);
      expect(h.files.selected, isNull);
      expect(
        inPane(find.textContaining('appear under the answer that made them')),
        findsOneWidget,
      );
      expect(
        inPane(find.textContaining('has no list of them all')),
        findsOneWidget,
      );
      expect(inPane(control('Refresh created files')), findsNothing);
      // It is asked once, not on every rebuild.
      expect(
        llm.calls.where((c) => c.startsWith('createdFiles')),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'a failed read shows why, is not retried by itself, and Refresh asks again',
    (tester) async {
      final llm = planningServer();
      llm.errors['createdFiles'] = const ApiException(
        'The server rejected the key.',
        status: 403,
      );
      final h = await openCreated(tester, [
        _file('project/report.pdf'),
      ], llm: llm);
      expect(
        inPane(find.text('Could not read the created files')),
        findsOneWidget,
      );
      expect(inPane(find.text('The server rejected the key.')), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(
        llm.calls.where((c) => c.startsWith('createdFiles')),
        hasLength(1),
      );
      llm.errors.remove('createdFiles');
      await tester.tap(inPane(control('Refresh created files')));
      await tester.pumpAndSettle();
      expect(
        llm.calls.where((c) => c.startsWith('createdFiles')),
        hasLength(2),
      );
      expect(inPane(find.text('report.pdf')), findsOneWidget);
      expect(
        inPane(find.text('Could not read the created files')),
        findsNothing,
      );
      expect(h.created.problem, isNull);
    },
  );

  testWidgets('another workspace shows its own files', (tester) async {
    final llm = planningServer();
    final h = await openCreated(tester, [
      _file('project/report.pdf'),
    ], llm: llm);
    final other = llm.spaces.firstWhere((w) => w.slug != h.chat.activeSlug);
    llm.created[other.slug] = _list([_file('project/household.txt')]);
    await h.chat.select(other.slug);
    await tester.pumpAndSettle();
    expect(inPane(find.text('household.txt')), findsOneWidget);
    expect(inPane(find.text('report.pdf')), findsNothing);
    expect(llm.calls, contains('createdFiles:${other.slug}'));
  });

  testWidgets(
    'long names and folders overflow nothing at the narrowest desktop width',
    (tester) async {
      final long = 'x' * 120;
      final h = await pumpApp(
        tester,
        llm: planningServer(),
        size: const Size(830, 700),
      );
      h.llm.created[h.chat.activeSlug!] = _list([
        _file(
          'threads/12/$long/$long.txt',
          area: CreatedArea.work,
          goes: threeDays,
        ),
        _file(
          'public/$long/$long.html',
          area: CreatedArea.public,
          url: 'https://host.example.ts.net:8447/q3/$long.html',
        ),
      ]);
      h.shell.showPane(Pane.files);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(FileTree),
          matching: control('Created files'),
        ),
      );
      await tester.pumpAndSettle();
      expect(inPane(find.text('2 files')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the phone does not list them', (tester) async {
    final h = await pumpApp(
      tester,
      llm: planningServer(),
      size: const Size(400, 800),
    );
    expect(find.byType(EssentialsPage), findsNothing);
    expect(h.llm.calls.where((c) => c.startsWith('createdFiles')), isEmpty);
  });
}
