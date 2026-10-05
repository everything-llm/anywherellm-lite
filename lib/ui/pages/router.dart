import 'package:flutter/widgets.dart';

import '../state/nav_controller.dart';
import 'connection_gate.dart';
import 'documents_pages.dart';
import 'settings_page.dart';
import 'upload_page.dart';
import 'workspaces_pages.dart';

/// The page for [route], behind the connection gate when the route needs a server.
Widget pageFor(AppRoute route) {
  final page = switch (route) {
    WorkspacesRoute() => const WorkspacesPage(),
    WorkspaceRoute(:final slug) => WorkspacePage(slug),
    DocumentsRoute() => const DocumentsPage(),
    DocumentRoute(:final path) => DocumentPage(path),
    UploadRoute() => const UploadPage(),
    SettingsRoute() => const SettingsPage(),
  };
  return route.needsServer ? ConnectionGate(child: page) : page;
}
