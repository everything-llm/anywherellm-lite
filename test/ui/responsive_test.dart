import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:everything/core/server_models.dart';
import 'package:everything/ui/sidebar.dart';
import 'package:everything/ui/state/nav_controller.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// One width per shell layout, and the window's own minimum (see my_application.cc).
const sizes = [Size(1400, 900), Size(780, 700), Size(500, 700), Size(360, 480)];

const longWord =
    'an-extremely-long-unbroken-name-that-has-no-place-to-wrap-and-must-not-overflow-anything';

/// Data that stresses every layout: long unbroken words and long descriptions.
FakeAnythingLlm awkward() {
  final doc = DocEntry(
    folder: 'folder-$longWord',
    name: 'file-$longWord.json',
    title: 'title-$longWord',
    description: 'A description that keeps going. ' * 12,
    author: 'author-$longWord',
    source: 'source-$longWord',
    published: '10/5/2026, 11:48:20 AM',
    words: 123456,
    tokens: 234567,
  );
  return FakeAnythingLlm()
    ..workspacesValue = [
      Workspace(
        slug: 'slug-$longWord',
        name: 'name-$longWord',
        chatModel: 'model-$longWord',
        threads: 3,
        documents: [WorkspaceDoc(path: doc.path, title: doc.title)],
      ),
    ]
    ..foldersValue = [
      DocFolder(name: doc.folder, docs: [doc]),
    ];
}

void main() {
  final doc = awkward().foldersValue.first.docs.first;
  final routes = <String, AppRoute>{
    'workspaces': const WorkspacesRoute(),
    'workspace': const WorkspaceRoute('slug-$longWord'),
    'documents': const DocumentsRoute(),
    'document': DocumentRoute(doc.path),
    'upload': const UploadRoute(),
    'settings': const SettingsRoute(),
  };

  for (final size in sizes) {
    for (final MapEntry(key: name, value: route) in routes.entries) {
      testWidgets(
        '$name fits at ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          await pumpApp(
            tester,
            llm: awkward(),
            connection: sampleConnection,
            size: size,
            route: route,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'the no-server page fits at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await pumpApp(tester, size: size);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('resizing through every layout keeps working', (tester) async {
    final h = await pumpApp(
      tester,
      llm: awkward(),
      connection: sampleConnection,
      size: sizes.first,
      route: const DocumentsRoute(),
    );
    for (final size in [...sizes, ...sizes.reversed]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'at ${size.width}');
    }
    expect(h.nav.route, const DocumentsRoute());
    expect(find.byType(Sidebar), findsOneWidget);
  });
}
