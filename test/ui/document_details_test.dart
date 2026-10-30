import 'dart:ui';

import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/settings/rows.dart';
import 'package:anywherellm/ui/sources/document_details.dart';
import 'package:anywherellm/ui/sources/sources_panel.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/widgets/controls.dart';
import 'package:anywherellm/ui/widgets/sheet.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/picker.dart';
import '../support/pump.dart';

/// [finder] in the Documents sheet.
Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(SourcesPanel), matching: finder);

/// [finder] in Document details.
Finder inDetails(Finder finder) =>
    find.descendant(of: find.byType(DocumentDetailsPage), matching: finder);

/// Q3 planning's server with Boiler manual.pdf in Manuals, which no workspace uses.
FakeAnythingLlm withManuals() {
  final llm = planningServer();
  libraryDoc(
    llm,
    'Boiler manual.pdf',
    words: 9300,
    folder: 'Manuals',
    published: '10/12/2026, 9:30:00 AM',
  );
  return llm;
}

/// The app on a phone, with the Documents sheet open over the chat.
Future<Harness> withDocuments(WidgetTester tester, FakeAnythingLlm llm) async {
  final h = await pumpApp(tester, llm: llm);
  h.shell.openSources();
  await tester.pumpAndSettle();
  return h;
}

/// The sheet with the details of [title] open over it.
Future<Harness> withDetails(
  WidgetTester tester,
  FakeAnythingLlm llm,
  String title,
) async {
  final h = await withDocuments(tester, llm);
  await tapVisible(tester, inSheet(control('Details of $title')));
  await tester.pumpAndSettle();
  return h;
}

/// The value at the end of Document details' row [term], as its words.
String fact(WidgetTester tester, String term) => tester
    .widgetList<Text>(
      find.descendant(
        of: find
            .ancestor(
              of: inDetails(find.text(term)),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byType(Text),
      ),
    )
    .skip(1)
    .map((t) => t.data)
    .join(' / ');

/// Whether a screen reader hears Move to folder's row [name] as the one chosen.
bool chosen(WidgetTester tester, String name) =>
    tester.getSemantics(control(name)).flagsCollection.isSelected ==
    Tristate.isTrue;

void main() {
  group('Documents', () {
    testWidgets('lists the library by folder once there is more than one', (
      tester,
    ) async {
      final h = await withDocuments(tester, withManuals());
      expect(inSheet(find.text('custom-documents')), findsOneWidget);
      expect(inSheet(find.text('Manuals')), findsOneWidget);
      expect(inSheet(find.text('Boiler manual.pdf')), findsOneWidget);
      expect(inSheet(find.text('Not used · 9,300 words')), findsOneWidget);
      // Each folder's name is heard as a heading over its documents.
      expect(
        find.ancestor(
          of: inSheet(find.text('Manuals')),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.header == true,
          ),
        ),
        findsOneWidget,
      );
      final heading = tester.getTopLeft(inSheet(find.text('Manuals'))).dy;
      expect(
        tester.getTopLeft(inSheet(find.text('Boiler manual.pdf'))).dy,
        greaterThan(heading),
      );
      expect(h.sources.files.where((f) => f.on), hasLength(2));
    });

    testWidgets('one folder has no heading', (tester) async {
      await withDocuments(tester, planningServer());
      expect(inSheet(find.text('custom-documents')), findsNothing);
      expect(inSheet(find.byType(FolderHeading)), findsNothing);
    });

    testWidgets('a switch adds a document to the workspace or takes it out', (
      tester,
    ) async {
      final h = await withDocuments(tester, withManuals());
      await tapVisible(
        tester,
        inSheet(control('Use Boiler manual.pdf in answers')),
      );
      await tester.pumpAndSettle();
      expect(
        h.llm.calls,
        contains('updateEmbeddings:+Manuals/Boiler manual.pdf.json-'),
      );
      expect(inSheet(find.text('9,300 words')), findsOneWidget);
      expect(find.text('Q3 planning · 3 docs in use'), findsOneWidget);

      await tapVisible(
        tester,
        inSheet(control('Use Boiler manual.pdf in answers')),
      );
      await tester.pumpAndSettle();
      expect(
        h.llm.calls,
        contains('updateEmbeddings:+-Manuals/Boiler manual.pdf.json'),
      );
      // Out of the workspace, it stays in the library and on the list.
      expect(inSheet(find.text('Not used · 9,300 words')), findsOneWidget);
      expect(h.llm.library, hasLength(3));
    });

    testWidgets('the file picker offers only the types the server reads', (
      tester,
    ) async {
      final picker = FakePicker([]);
      FilePickerPlatform.instance = picker;
      await withDocuments(tester, planningServer());
      await tapVisible(tester, inSheet(control('Add a file')));
      await tester.pumpAndSettle();
      expect(picker.type, FileType.custom);
      expect(picker.allowedExtensions, ['md', 'pdf', 'txt']);
    });

    testWidgets('a type list the server will not give leaves any file', (
      tester,
    ) async {
      final picker = FakePicker([]);
      FilePickerPlatform.instance = picker;
      final llm = planningServer()
        ..errors['acceptedExtensions'] = const ApiException('busy');
      await withDocuments(tester, llm);
      await tapVisible(tester, inSheet(control('Add a file')));
      await tester.pumpAndSettle();
      expect((picker.type, picker.allowedExtensions), (FileType.any, null));
    });
  });

  group('Document details', () {
    testWidgets('shows whether it is used, its folder and what it is', (
      tester,
    ) async {
      final h = await withDetails(tester, withManuals(), 'Boiler manual.pdf');
      expect(h.shell.document, 'Boiler manual.pdf.json');
      expect(find.text('Document details'), findsOneWidget);
      // Its title, and the file it came from under Source.
      expect(inDetails(find.text('Boiler manual.pdf')), findsNWidgets(2));
      expect(inDetails(control('Used in answers')), findsOneWidget);
      expect(
        inDetails(control('Folder: Manuals. Move to another folder')),
        findsOneWidget,
      );
      expect(inDetails(find.text('PDF')), findsOneWidget);
      expect(fact(tester, 'Words'), '9,300');
      expect(fact(tester, 'Added'), '12 Oct 2026');
      expect(fact(tester, 'Source'), 'Uploaded file / Boiler manual.pdf');
      // Not used here, it cannot be read in full.
      final full = tester.widget<AppSwitch>(
        find.descendant(
          of: inDetails(find.byType(FieldRow)).at(1),
          matching: find.byType(AppSwitch),
        ),
      );
      expect((full.value, full.onChanged), (false, null));
      // Folders cannot be deleted here, and a document has no text to show.
      expect(find.textContaining('Delete folder'), findsNothing);
      expect(h.llm.calls.where((c) => c.startsWith('document:')), isEmpty);
    });

    testWidgets('Used in answers and Read in full change the workspace', (
      tester,
    ) async {
      final h = await withDetails(tester, withManuals(), 'Boiler manual.pdf');
      await tester.tap(inDetails(control('Used in answers')));
      await tester.pumpAndSettle();
      expect(h.sources.byName('Boiler manual.pdf.json')!.on, isTrue);
      await tester.tap(inDetails(control('Read in full')));
      await tester.pumpAndSettle();
      expect(
        h.llm.calls,
        contains('pinDocument:q3:Manuals/Boiler manual.pdf.json:true'),
      );
      expect(h.sources.byName('Boiler manual.pdf.json')!.pinned, isTrue);
      await tester.tap(control('Back to Documents'));
      await tester.pumpAndSettle();
      expect(inSheet(find.text('9,300 words · Read in full')), findsOneWidget);
    });

    testWidgets('Move to folder moves it, and it stays open', (tester) async {
      final h = await withDetails(tester, withManuals(), 'Boiler manual.pdf');
      await tester.tap(
        inDetails(control('Folder: Manuals. Move to another folder')),
      );
      await tester.pumpAndSettle();
      expect(h.shell.popup.value, Popup.moveDocument);
      expect(find.text('Move to folder'), findsOneWidget);
      expect(chosen(tester, 'Manuals'), isTrue);
      expect(chosen(tester, 'custom-documents'), isFalse);
      await tester.tap(control('custom-documents'));
      await tester.pumpAndSettle();
      await tester.tap(control('Move'));
      await tester.pumpAndSettle();
      expect(
        h.llm.calls,
        contains(
          'moveDocuments:Manuals/Boiler manual.pdf.json>'
          'custom-documents/Boiler manual.pdf.json',
        ),
      );
      expect(h.shell.popup.value, isNull);
      expect(h.shell.document, 'Boiler manual.pdf.json');
      expect(
        inDetails(control('Folder: custom-documents. Move to another folder')),
        findsOneWidget,
      );
      expect(h.prefs.lastFolder, 'custom-documents');
    });

    testWidgets('a new folder is made, chosen and moved into', (tester) async {
      final h = await withDetails(tester, withManuals(), 'Boiler manual.pdf');
      h.shell.togglePopup(Popup.moveDocument);
      await tester.pumpAndSettle();
      await tester.enterText(
        typingField(find.byType(ModalSheet)),
        'Bills and papers',
      );
      await tester.tap(control('Create'));
      await tester.pumpAndSettle();
      expect(h.llm.calls, contains('createFolder:Bills and papers'));
      expect(chosen(tester, 'Bills and papers'), isTrue);
      await tester.tap(control('Move'));
      await tester.pumpAndSettle();
      expect(
        h.sources.byName('Boiler manual.pdf.json')!.folder,
        'Bills and papers',
      );
    });

    testWidgets('a folder name that is a path is refused in the sheet', (
      tester,
    ) async {
      final h = await withDetails(tester, withManuals(), 'Boiler manual.pdf');
      h.shell.togglePopup(Popup.moveDocument);
      await tester.pumpAndSettle();
      await tester.enterText(typingField(find.byType(ModalSheet)), 'a/b');
      await tester.tap(control('Create'));
      await tester.pumpAndSettle();
      expect(find.text('Could not make the folder'), findsOneWidget);
      expect(h.llm.calls.where((c) => c.startsWith('createFolder')), isEmpty);
    });

    testWidgets('Delete from server asks first, then deletes and closes', (
      tester,
    ) async {
      final h = await withDetails(tester, withManuals(), 'Boiler manual.pdf');
      await tapVisible(tester, inDetails(control('Delete from server')));
      await tester.pumpAndSettle();
      expect(h.shell.popup.value, Popup.deleteDocument);
      expect(
        find.text(
          'Delete Boiler manual.pdf from the server? Every workspace loses it. This '
          'can\'t be undone.',
        ),
        findsOneWidget,
      );
      await tester.tap(asked('Keep'));
      await tester.pumpAndSettle();
      expect(
        h.llm.calls.where((c) => c.startsWith('deleteDocuments')),
        isEmpty,
      );
      expect(h.shell.document, 'Boiler manual.pdf.json');

      await tapVisible(tester, inDetails(control('Delete from server')));
      await tester.pumpAndSettle();
      await tester.tap(asked('Delete from server'));
      await tester.pumpAndSettle();
      expect(
        h.llm.calls,
        contains('deleteDocuments:Manuals/Boiler manual.pdf.json'),
      );
      expect(h.shell.document, isNull);
      expect(find.byType(DocumentDetailsPage), findsNothing);
      expect(inSheet(find.text('Boiler manual.pdf')), findsNothing);
    });

    testWidgets('a web page shows its address whole', (tester) async {
      final llm = planningServer();
      llm.library['custom-documents/url-example.com-1.json'] = const LibraryDoc(
        path: 'custom-documents/url-example.com-1.json',
        title: 'Example pricing',
        web: true,
        link: 'https://example.com/pricing/for/very/long/addresses',
      );
      await withDetails(tester, llm, 'Example pricing');
      expect(inDetails(find.text('WEB')), findsOneWidget);
      expect(
        fact(tester, 'Source'),
        'Web page / https://example.com/pricing/for/very/long/addresses',
      );
      expect(inDetails(find.text('Words')), findsNothing);
    });

    testWidgets('a document gone from the library closes its details', (
      tester,
    ) async {
      final h = await withDetails(tester, withManuals(), 'Boiler manual.pdf');
      h.llm.library.remove('Manuals/Boiler manual.pdf.json');
      await h.sources.refresh();
      await tester.pumpAndSettle();
      expect(h.shell.document, isNull);
      expect(find.byType(DocumentDetailsPage), findsNothing);
    });
  });
}
