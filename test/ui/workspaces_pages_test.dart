import 'package:everything/core/ports.dart';
import 'package:everything/core/server_models.dart';
import 'package:everything/ui/state/nav_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

FakeAnythingLlm _server() => FakeAnythingLlm()
  ..workspacesValue = [
    const Workspace(
      slug: 'research',
      name: 'Research',
      chatModel: 'llama3',
      threads: 2,
      documents: [
        WorkspaceDoc(path: 'claude/agents.md-1.json', title: 'Agents'),
      ],
    ),
    const Workspace(slug: 'algorithms', name: 'AnythingLLM', threads: 1),
  ];

void main() {
  group('with no server set up', () {
    testWidgets('a section points to Settings and asks the server nothing', (
      tester,
    ) async {
      final h = await pumpApp(tester);
      expect(find.text('Add your AnythingLLM server'), findsOneWidget);
      expect(h.llm.calls, isEmpty);
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const SettingsRoute());
    });

    testWidgets('saving a connection opens the section on the server', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: _server());
      await h.settings.save('https://h:3001', 'K1');
      await tester.pumpAndSettle();
      expect(find.text('Add your AnythingLLM server'), findsNothing);
      expect(find.text('AnythingLLM'), findsOneWidget);
      expect(h.llm.calls, ['workspaces']);
    });

    testWidgets('removing the connection brings the pointer back', (
      tester,
    ) async {
      final h = await pumpApp(
        tester,
        llm: _server(),
        connection: sampleConnection,
      );
      await h.settings.clear();
      await tester.pumpAndSettle();
      expect(find.text('Add your AnythingLLM server'), findsOneWidget);
    });
  });

  group('the workspaces', () {
    testWidgets('list each name with its slug, model and threads', (
      tester,
    ) async {
      await pumpApp(tester, llm: _server(), connection: sampleConnection);
      expect(find.text('Research'), findsOneWidget);
      expect(find.text('research, llama3, 2 threads'), findsOneWidget);
      expect(find.text('algorithms, 1 thread'), findsOneWidget);
    });

    testWidgets('say so when there are none', (tester) async {
      await pumpApp(tester, connection: sampleConnection);
      expect(find.text('No workspaces yet'), findsOneWidget);
    });

    testWidgets('show the server\'s refusal', (tester) async {
      final llm = FakeAnythingLlm()
        ..errors['workspaces'] = const ApiException(
          'The server rejected the key.',
          status: 403,
        );
      await pumpApp(tester, llm: llm, connection: sampleConnection);
      expect(find.text('Could not load this page'), findsOneWidget);
      expect(find.text('The server rejected the key.'), findsOneWidget);
    });

    testWidgets('a row opens the workspace with its documents', (tester) async {
      final h = await pumpApp(
        tester,
        llm: _server(),
        connection: sampleConnection,
      );
      await tester.tap(find.text('Research'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const WorkspaceRoute('research'));
      expect(h.llm.calls, contains('workspace:research'));
      expect(find.text('llama3'), findsOneWidget);
      expect(find.text('1 document'), findsOneWidget);
      await tester.tap(find.text('Agents'));
      await tester.pumpAndSettle();
      expect(h.nav.route, const DocumentRoute('claude/agents.md-1.json'));
    });
  });

  group('a workspace', () {
    testWidgets('with no model and no documents says so', (tester) async {
      await pumpApp(
        tester,
        llm: _server(),
        connection: sampleConnection,
        route: const WorkspaceRoute('algorithms'),
      );
      expect(find.text('the server default'), findsOneWidget);
      expect(find.text('No documents in this workspace'), findsOneWidget);
    });

    testWidgets('the breadcrumb goes back to the list', (tester) async {
      final h = await pumpApp(
        tester,
        llm: _server(),
        connection: sampleConnection,
        route: const WorkspaceRoute('algorithms'),
      );
      await tester.tap(find.text('Workspaces').last);
      await tester.pumpAndSettle();
      expect(h.nav.route, const WorkspacesRoute());
    });
  });
}
