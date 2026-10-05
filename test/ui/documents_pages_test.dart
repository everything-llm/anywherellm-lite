import 'package:everything/core/ports.dart';
import 'package:everything/core/server_models.dart';
import 'package:everything/ui/state/nav_controller.dart';
import 'package:everything/ui/widgets/rows.dart';
import 'package:everything/ui/widgets/select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// The page's own scrollable, not the sidebar's.
final pageScroll = find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

final _agents = heldDoc;

/// [documentServer], with a second folder and a second document beside [heldDoc].
FakeAnythingLlm _server() {
  final llm = documentServer();
  return llm
    ..foldersValue = [
      DocFolder(
        name: 'custom-documents',
        docs: [sampleDoc('custom-documents', 'deploy')],
      ),
      DocFolder(name: 'claude', docs: [_agents, sampleDoc('claude', 'models')]),
    ];
}

Future<void> _open(WidgetTester tester, [FakeAnythingLlm? llm]) => pumpApp(
  tester,
  llm: llm ?? _server(),
  connection: sampleConnection,
  route: const DocumentsRoute(),
);

void main() {
  group('the list', () {
    testWidgets('groups the documents by folder and counts them', (
      tester,
    ) async {
      await _open(tester);
      expect(find.text('3 documents'), findsOneWidget);
      expect(find.text('custom-documents'), findsOneWidget);
      expect(find.text('claude'), findsOneWidget);
      expect(find.text('About agents'), findsOneWidget);
    });

    testWidgets('a search narrows the list and can be cleared', (tester) async {
      await _open(tester);
      await tester.enterText(find.byType(TextField), 'DEPLOY');
      await tester.pumpAndSettle();
      expect(find.text('About deploy'), findsOneWidget);
      expect(find.text('About agents'), findsNothing);
      expect(find.text('Showing 1 of 3 documents'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('About agents'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('the folder select narrows to one folder', (tester) async {
      await _open(tester);
      await tester.tap(find.byType(NilsSelect));
      await tester.pumpAndSettle();
      await tester.tap(find.text('claude (2)'));
      await tester.pumpAndSettle();
      expect(find.text('About deploy'), findsNothing);
      expect(find.text('Showing 2 of 3 documents'), findsOneWidget);
    });

    testWidgets('a filter that matches nothing says so', (tester) async {
      await _open(tester);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches'), findsOneWidget);
    });

    testWidgets('an empty server says how to add one, with no filters', (
      tester,
    ) async {
      await _open(tester, FakeAnythingLlm());
      expect(find.text('No documents yet'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('builds only the rows near the screen', (tester) async {
      final llm = FakeAnythingLlm()
        ..foldersValue = [
          DocFolder(
            name: 'area',
            docs: [
              for (var i = 0; i < 300; i++)
                sampleDoc('area', 'doc${i.toString().padLeft(3, '0')}'),
            ],
          ),
        ];
      await _open(tester, llm);
      expect(find.text('doc000'), findsOneWidget);
      expect(find.text('doc299'), findsNothing);
      expect(find.byType(NilsRow).evaluate().length, lessThan(60));
      await tester.scrollUntilVisible(
        find.text('doc299'),
        600,
        scrollable: pageScroll,
      );
      expect(find.text('doc299'), findsOneWidget);
    });

    testWidgets('a row opens the document', (tester) async {
      final h = await pumpApp(
        tester,
        llm: _server(),
        connection: sampleConnection,
        route: const DocumentsRoute(),
      );
      await tester.tap(find.text('agents'));
      await tester.pumpAndSettle();
      expect(h.nav.route, DocumentRoute(_agents.path));
    });
  });

  group('a document', () {
    Future<Harness> openAgents(WidgetTester tester) => pumpApp(
      tester,
      llm: _server(),
      connection: sampleConnection,
      route: DocumentRoute(_agents.path),
    );

    testWidgets('shows what the server knows of it', (tester) async {
      await openAgents(tester);
      expect(find.text('agents'), findsOneWidget);
      expect(find.text('About agents'), findsOneWidget);
      expect(find.text(_agents.name), findsOneWidget);
      expect(find.text('10/5/2026, 11:48:20 AM'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.textContaining('does not return a document'), findsOneWidget);
    });

    testWidgets('lists only the workspaces that hold it, and opens one', (
      tester,
    ) async {
      final h = await openAgents(tester);
      expect(find.text('In workspaces'), findsOneWidget);
      expect(find.text('Research'), findsOneWidget);
      expect(find.text('Other'), findsNothing);
      await tester.tap(find.text('Research'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const WorkspaceRoute('research'));
    });

    testWidgets('in no workspace says so', (tester) async {
      final llm = _server();
      await pumpApp(
        tester,
        llm: llm,
        connection: sampleConnection,
        route: DocumentRoute(llm.foldersValue.first.docs.first.path),
      );
      expect(find.text('In no workspace'), findsOneWidget);
    });

    testWidgets('that is gone says so', (tester) async {
      await pumpApp(
        tester,
        llm: _server(),
        connection: sampleConnection,
        route: const DocumentRoute('claude/gone.json'),
      );
      expect(
        find.text('There is no document claude/gone.json on the server.'),
        findsOneWidget,
      );
    });

    testWidgets('shows a failure reading a workspace', (tester) async {
      final llm = _server()
        ..errors['workspace'] = const ApiException('server down', status: 500);
      await pumpApp(
        tester,
        llm: llm,
        connection: sampleConnection,
        route: DocumentRoute(_agents.path),
      );
      expect(find.text('server down'), findsOneWidget);
    });

    testWidgets('the breadcrumb goes back to the list', (tester) async {
      final h = await openAgents(tester);
      await tester.tap(find.text('Documents').last);
      await tester.pumpAndSettle();
      expect(h.nav.route, const DocumentsRoute());
    });
  });
}
