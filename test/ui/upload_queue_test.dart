import 'package:anywherellm/core/upload.dart';
import 'package:anywherellm/ui/files/files_view.dart';
import 'package:anywherellm/ui/sources/sources_panel.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/widgets/drop_zone.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

Finder control(String label) => find.byWidgetPredicate(
  (widget) => widget is Tappable && widget.label == label,
);

UploadFile file(String name) => UploadFile(name: name, read: () async => [1]);

/// Hands [files] to the drop zone inside [area], as a drop or the picker would.
Future<void> drop(
  WidgetTester tester,
  Type area,
  List<UploadFile> files,
) async {
  final zone = tester.widget<DropZone>(
    find.descendant(of: find.byType(area), matching: find.byType(DropZone)),
  );
  await zone.onFiles(files);
  await tester.pumpAndSettle();
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

void main() {
  testWidgets('dropped files wait in a list until Add', (tester) async {
    final llm = planningServer();
    await pumpApp(tester, llm: llm);
    await drop(tester, SourcesPanel, [file('a.md'), file('b.md')]);
    expect(find.text('a.md'), findsOneWidget);
    expect(llm.calls.where((c) => c.startsWith('upload')), isEmpty);
    expect(control('Add 2 files'), findsOneWidget);
    await tester.tap(control('Remove b.md'));
    await tester.pumpAndSettle();
    expect(find.text('b.md'), findsNothing);
    await tester.tap(control('Add 1 file'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('upload:a.md'));
    expect(llm.calls, isNot(contains('upload:b.md')));
    expect(control('Add 1 file'), findsNothing);
  });

  testWidgets('details typed for one file go with that file only', (
    tester,
  ) async {
    final llm = planningServer();
    await pumpApp(tester, llm: llm);
    await drop(tester, SourcesPanel, [file('a.md'), file('b.md')]);
    await tester.tap(control('Details of a.md'));
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
    await tester.tap(control('Add 2 files'));
    await tester.pumpAndSettle();
    expect(llm.metaOf['custom-documents/a.md.json']?.author, 'Ada');
    expect(llm.metaOf['custom-documents/a.md.json']?.title, 'Plan');
    expect(llm.metaOf['custom-documents/b.md.json']?.isEmpty, isTrue);
  });

  testWidgets('Cancel sends nothing and a file dropped twice is listed once', (
    tester,
  ) async {
    final llm = planningServer();
    await pumpApp(tester, llm: llm);
    await drop(tester, SourcesPanel, [file('a.md')]);
    await drop(tester, SourcesPanel, [file('a.md')]);
    expect(find.text('a.md'), findsOneWidget);
    await tester.tap(control('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('a.md'), findsNothing);
    expect(llm.calls.where((c) => c.startsWith('upload')), isEmpty);
  });

  testWidgets('a file for a Files folder waits for Add too', (tester) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm);
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();
    await h.files.select('/library/custom-documents');
    await tester.pumpAndSettle();
    await drop(tester, FilesView, [file('a.md')]);
    expect(llm.calls.where((c) => c.startsWith('upload')), isEmpty);
    await tester.ensureVisible(control('Add 1 file'));
    await tester.tap(control('Add 1 file'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('upload:custom-documents/a.md'));
  });

  testWidgets('a link goes with its details', (tester) async {
    final llm = planningServer();
    await pumpApp(tester, llm: llm);
    await tester.tap(control('Add a link'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: field('Web page to add'),
        matching: find.byType(TextField),
      ),
      'https://example.com',
    );
    await tester.tap(control('Details'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: field('Source'), matching: find.byType(TextField)),
      'Finance',
    );
    await tester.tap(control('Add'));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('uploadLink:https://example.com'));
    expect(
      llm.metaOf['custom-documents/url-example.com.json']?.source,
      'Finance',
    );
  });
}
