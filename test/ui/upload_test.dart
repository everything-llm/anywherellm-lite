import 'package:everything/core/ports.dart';
import 'package:everything/core/server_models.dart';
import 'package:everything/core/upload.dart';
import 'package:everything/ui/state/nav_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';
import '../support/rig.dart';

UploadFile _file(String name, {Object? error}) => UploadFile(
  name: name,
  read: () async {
    if (error != null) throw error;
    return [1, 2, 3];
  },
);

void main() {
  group('the controller', () {
    late Rig rig;

    setUp(() {
      rig = Rig()
        ..llm.foldersValue = [
          const DocFolder(name: 'claude', docs: []),
          const DocFolder(name: 'custom-documents', docs: []),
        ];
    });
    tearDown(() => rig.dispose());

    test('reads what the server accepts and its folders', () async {
      await rig.upload.refresh();
      expect(rig.upload.accepted, {'.md', '.txt', '.pdf'});
      expect(rig.upload.folders, ['custom-documents', 'claude']);
      expect(rig.upload.problems, isEmpty);
    });

    test('sends each file into the chosen folder', () async {
      await rig.upload.refresh();
      rig.upload.choose('claude');
      await rig.upload.upload([_file('a.md'), _file('b.pdf')]);
      expect(
        rig.llm.calls,
        containsAll(['upload:a.md:claude', 'upload:b.pdf:claude']),
      );
      expect(rig.upload.uploaded.map((d) => d.title), ['b.pdf', 'a.md']);
      expect(rig.upload.sending, isNull);
    });

    test(
      'refuses a type the server does not read, and still sends the rest',
      () async {
        await rig.upload.refresh();
        await rig.upload.upload([_file('x.exe'), _file('a.md')]);
        expect(rig.llm.calls, isNot(contains(startsWith('upload:x.exe'))));
        expect(rig.upload.problems.single.title, 'Could not upload x.exe');
        expect(
          rig.upload.problems.single.text,
          'the server does not read .exe files',
        );
        expect(rig.upload.uploaded.single.title, 'a.md');
      },
    );

    test('lets the server decide when it has not said what it reads', () async {
      rig.llm.errors['acceptedExtensions'] = const ApiException('down');
      await rig.upload.refresh();
      expect(
        rig.upload.problems.single.title,
        'Could not ask the server what it reads',
      );
      await rig.upload.upload([_file('x.exe')]);
      expect(rig.llm.calls, contains('upload:x.exe:custom-documents'));
    });

    test('says why a file could not be read or was refused', () async {
      await rig.upload.refresh();
      rig.llm.errors['upload'] = const ApiException('Collector is offline');
      await rig.upload.upload([
        _file(
          'gone.md',
          error: const UnreadableFile('the file could not be read'),
        ),
        _file('a.md'),
      ]);
      expect(rig.upload.problems.map((p) => p.text), [
        'the file could not be read',
        'Collector is offline',
      ]);
    });

    test('a new server starts afresh', () async {
      final r = Rig(connection: sampleConnection);
      addTearDown(r.dispose);
      await r.upload.refresh();
      r.upload.choose('claude');
      await r.upload.upload([_file('a.md'), _file('x.exe')]);
      await r.settings.save('https://other:3001', 'K2');
      await r.upload.refresh();
      expect(r.upload.uploaded, isEmpty);
      expect(r.upload.problems, isEmpty);
      expect(r.upload.folder, 'custom-documents');
    });

    test('a new batch forgets the last batch\'s refusals', () async {
      await rig.upload.refresh();
      await rig.upload.upload([_file('x.exe')]);
      await rig.upload.upload([_file('a.md')]);
      expect(rig.upload.problems, isEmpty);
    });
  });

  group('the page', () {
    testWidgets('asks the server what it reads and shows the folder', (
      tester,
    ) async {
      final h = await pumpApp(
        tester,
        connection: sampleConnection,
        route: const UploadRoute(),
      );
      expect(h.llm.calls, containsAll(['acceptedExtensions', 'documents']));
      expect(find.text('Folder: custom-documents'), findsOneWidget);
      expect(find.text('The server reads .md .pdf .txt'), findsOneWidget);
      expect(find.text('Drop files here, or click to browse'), findsOneWidget);
    });

    testWidgets('lists what was uploaded, and a row opens it', (tester) async {
      final h = await pumpApp(
        tester,
        connection: sampleConnection,
        route: const UploadRoute(),
      );
      await h.upload.upload([_file('notes.md')]);
      await tester.pumpAndSettle();
      expect(find.text('Uploaded'), findsOneWidget);
      await tester.tap(find.text('notes.md'));
      await tester.pumpAndSettle();
      expect(
        h.nav.route,
        const DocumentRoute('custom-documents/notes.md-1.json'),
      );
      expect(find.text('notes.md'), findsOneWidget);
    });

    testWidgets('shows each refusal', (tester) async {
      final h = await pumpApp(
        tester,
        connection: sampleConnection,
        route: const UploadRoute(),
      );
      await h.upload.upload([_file('x.exe')]);
      await tester.pumpAndSettle();
      expect(find.text('Could not upload x.exe'), findsOneWidget);
    });
  });
}
