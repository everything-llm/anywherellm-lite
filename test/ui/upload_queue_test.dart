import 'package:anywherellm/ui/sources/sources_panel.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/picker.dart';
import '../support/pump.dart';

/// Opens Documents over the chat.
Future<Harness> openDocuments(WidgetTester tester, FakeAnythingLlm llm) async {
  final h = await pumpApp(tester, llm: llm);
  h.shell.openSources();
  await tester.pumpAndSettle();
  return h;
}

/// Picks [names] with Documents' Add a file, as the file picker would give them.
Future<void> pick(WidgetTester tester, List<String> names) async {
  FilePickerPlatform.instance = FakePicker([for (final n in names) Picked(n)]);
  await tapVisible(
    tester,
    find.descendant(
      of: find.byType(SourcesPanel),
      matching: control('Add a file'),
    ),
  );
  await tester.pumpAndSettle();
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

void main() {
  testWidgets('picked files wait in a list until Add', (tester) async {
    final llm = planningServer();
    await openDocuments(tester, llm);
    await pick(tester, ['a.md', 'b.md']);
    expect(find.text('a.md'), findsOneWidget);
    expect(llm.calls.where((c) => c.startsWith('upload')), isEmpty);
    expect(control('Add 2 files'), findsOneWidget);
    await tapVisible(tester, control('Remove b.md'));
    await tester.pumpAndSettle();
    expect(find.text('b.md'), findsNothing);
    await tapVisible(tester, control('Add 1 file'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('upload:a.md'));
    expect(llm.calls, isNot(contains('upload:b.md')));
    expect(control('Add 1 file'), findsNothing);
  });

  testWidgets('details typed for one file go with that file only', (
    tester,
  ) async {
    final llm = planningServer();
    await openDocuments(tester, llm);
    await pick(tester, ['a.md', 'b.md']);
    await tapVisible(tester, control('Details of a.md'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: field('Author of a.md'),
        matching: find.byType(TextField),
      ),
      'Ada',
    );
    await tester.enterText(
      find.descendant(
        of: field('Title of a.md'),
        matching: find.byType(TextField),
      ),
      'Plan',
    );
    await tapVisible(tester, control('Add 2 files'));
    await tester.pumpAndSettle();
    expect(llm.metaOf['custom-documents/a.md.json']?.author, 'Ada');
    expect(llm.metaOf['custom-documents/a.md.json']?.title, 'Plan');
    expect(llm.metaOf['custom-documents/b.md.json']?.isEmpty, isTrue);
  });

  testWidgets('Cancel sends nothing and a file picked twice is listed once', (
    tester,
  ) async {
    final llm = planningServer();
    await openDocuments(tester, llm);
    await pick(tester, ['a.md']);
    await pick(tester, ['a.md']);
    expect(find.text('a.md'), findsOneWidget);
    await tapVisible(tester, control('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('a.md'), findsNothing);
    expect(llm.calls.where((c) => c.startsWith('upload')), isEmpty);
  });

  testWidgets('a link goes with its details', (tester) async {
    final llm = planningServer();
    await openDocuments(tester, llm);
    await tapVisible(tester, control('Add a link'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: field('Web page to add'),
        matching: find.byType(TextField),
      ),
      'https://example.com',
    );
    await tapVisible(tester, control('Details'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: field('Source'), matching: find.byType(TextField)),
      'Finance',
    );
    await tapVisible(tester, control('Add'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('uploadLink:https://example.com'));
    expect(
      llm.metaOf['custom-documents/url-example.com.json']?.source,
      'Finance',
    );
  });

  testWidgets('what waits in Sources stays with its workspace', (tester) async {
    final llm = planningServer();
    final h = await openDocuments(tester, llm);
    await pick(tester, ['a.md']);
    await tapVisible(tester, control('Add a link'));
    await tester.pumpAndSettle();
    await h.chat.select('household');
    await tester.pumpAndSettle();
    expect(find.text('a.md'), findsNothing);
    expect(control('Add 1 file'), findsNothing);
    expect(field('Web page to add'), findsNothing);
  });

  testWidgets('a link that is not one keeps the form and its details', (
    tester,
  ) async {
    final llm = planningServer();
    final h = await openDocuments(tester, llm);
    await tapVisible(tester, control('Add a link'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: field('Web page to add'),
        matching: find.byType(TextField),
      ),
      'example.com/x',
    );
    await tapVisible(tester, control('Details'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: field('Source'), matching: find.byType(TextField)),
      'Finance',
    );
    await tapVisible(tester, control('Add'));
    await tester.pumpAndSettle();
    expect(llm.calls.where((c) => c.startsWith('uploadLink')), isEmpty);
    expect(h.sources.problems.single.title, 'Could not add the link');
    expect(find.text('example.com/x'), findsOneWidget);
    expect(find.text('Finance'), findsOneWidget);
    // Two taps with no frame between, as a quick double tap.
    await tapVisible(tester, control('Add'));
    await tester.tap(control('Add'));
    await tester.pumpAndSettle();
    expect(h.sources.problems, hasLength(1));
  });
}
