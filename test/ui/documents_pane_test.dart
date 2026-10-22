import 'dart:ui';

import 'package:anywherellm/ui/files/documents_pane.dart';
import 'package:anywherellm/ui/files/workspace_pages.dart';
import 'package:anywherellm/ui/sidebar.dart';
import 'package:anywherellm/ui/sources/sources_panel.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

const _desktop = Size(1440, 900);
const _split = Size(960, 600);
const _narrow = Size(800, 900);

Finder _inPane(Finder finder) =>
    find.descendant(of: find.byType(DocumentsPane), matching: finder);

/// The app at [size], on the Documents pane.
Future<Harness> _open(WidgetTester tester, Size size) async {
  final h = await pumpApp(tester, llm: planningServer(), size: size);
  await tester.pumpAndSettle();
  h.shell.openPane(Pane.documents);
  await tester.pumpAndSettle();
  return h;
}

/// Whether the row a screen reader hears as starting with [title] is the one chosen.
bool _chosen(WidgetTester tester, String title) {
  final row = tester.getSemantics(
    _inPane(find.bySemanticsLabel(RegExp('^${RegExp.escape(title)},'))).first,
  );
  return row.flagsCollection.isSelected == Tristate.isTrue;
}

void main() {
  testWidgets('the sidebar opens Documents beside the first one\'s text', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer(), size: _desktop);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(Sidebar),
        matching: find.text('Documents'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DocumentsPane), findsOneWidget);
    expect(_inPane(find.text('The text of Q3 roadmap.pdf.')), findsOneWidget);
    expect(_chosen(tester, 'Q3 roadmap.pdf'), isTrue);

    await tester.tap(_inPane(find.text('Customer interviews.docx')));
    await tester.pumpAndSettle();
    expect(
      _inPane(find.text('The text of Customer interviews.docx.')),
      findsOneWidget,
    );
    expect(_chosen(tester, 'Customer interviews.docx'), isTrue);
    expect(_chosen(tester, 'Q3 roadmap.pdf'), isFalse);
  });

  testWidgets('a switch in the list turns a document off', (tester) async {
    final h = await _open(tester, _desktop);

    await tester.tap(control('Use Q3 roadmap.pdf in answers'));
    await tester.pumpAndSettle();

    expect(
      h.llm.calls,
      contains('updateEmbeddings:+-custom-documents/Q3 roadmap.pdf.json'),
    );
    expect(_inPane(find.text('Not used · 120 words')), findsOneWidget);
  });

  testWidgets('Remove from workspace asks first', (tester) async {
    final h = await _open(tester, _desktop);

    await tester.tap(_inPane(find.text('Remove from workspace')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Remove Q3 roadmap.pdf from Q3'),
      findsOneWidget,
    );

    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(h.llm.calls.where((c) => c.startsWith('updateEmbeddings')), isEmpty);

    await tester.tap(_inPane(find.text('Remove from workspace')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(
      h.llm.calls,
      contains('updateEmbeddings:+-custom-documents/Q3 roadmap.pdf.json'),
    );
    expect(_inPane(find.text('Removed Q3 roadmap.pdf')), findsOneWidget);
    // The undo lasts its while.
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('Documents opens as the pane on a wide window', (tester) async {
    final h = await pumpApp(tester, llm: planningServer(), size: _split);
    await tester.pumpAndSettle();
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(WorkspacePages),
        matching: find.text('Documents'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DocumentsPane), findsOneWidget);
    expect(find.byType(SourcesPanel), findsNothing);
  });

  testWidgets('Documents opens as the sheet on a phone', (tester) async {
    final h = await pumpApp(tester, llm: planningServer());
    await tester.pumpAndSettle();
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(WorkspacePages),
        matching: find.text('Documents'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SourcesPanel), findsOneWidget);
    expect(find.byType(DocumentsPane), findsNothing);
  });

  testWidgets('from the workspace\'s pages, Back goes back to them', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer(), size: _split);
    await tester.pumpAndSettle();
    h.shell.showPane(Pane.files);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(WorkspacePages),
        matching: find.text('Documents'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DocumentsPane), findsOneWidget);

    await tester.tap(control('Back to the workspace'));
    await tester.pumpAndSettle();
    expect(find.byType(DocumentsPane), findsNothing);
    expect(find.byType(WorkspacePages), findsOneWidget);
  });

  testWidgets('narrower, a document\'s text takes the list\'s place', (
    tester,
  ) async {
    await _open(tester, _narrow);
    expect(_inPane(find.text('The text of Q3 roadmap.pdf.')), findsNothing);

    await tester.tap(_inPane(find.text('Q3 roadmap.pdf')));
    await tester.pumpAndSettle();
    expect(_inPane(find.text('The text of Q3 roadmap.pdf.')), findsOneWidget);
    expect(_inPane(find.text('Customer interviews.docx')), findsNothing);

    await tester.tap(control('Back to Documents'));
    await tester.pumpAndSettle();
    expect(_inPane(find.text('Customer interviews.docx')), findsOneWidget);
  });

  for (final (size, scale) in [
    (_desktop, 1.0),
    (_split, 1.0),
    (_narrow, 1.0),
    (_split, 2.0),
  ]) {
    testWidgets(
      'the pane fits at ${size.width.toInt()}x${size.height.toInt()}, '
      '${(scale * 100).toInt()}% text',
      (tester) async {
        final dispatcher = tester.platformDispatcher;
        dispatcher.textScaleFactorTestValue = scale;
        addTearDown(dispatcher.clearTextScaleFactorTestValue);
        await _open(tester, size);
        expect(tester.takeException(), isNull);

        await tester.tap(_inPane(find.text('Add a link')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(_inPane(find.text('Cancel')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(_inPane(find.text('Test a question')));
        await tester.tap(_inPane(find.text('Test a question')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
