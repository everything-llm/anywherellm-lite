import 'package:flutter/foundation.dart';

/// Where the app is.
///
/// Two routes are equal when they are the same kind and carry the same [arg].
@immutable
sealed class AppRoute {
  const AppRoute(this.section, [this.arg]);

  /// Which sidebar entry lights up.
  final String section;

  /// The path or name a page is about, for the routes that have one.
  final String? arg;

  /// The page one step up: a document goes back to its list. Null on a section's own page.
  AppRoute? get up => null;

  /// Whether the page reads the server, so it waits behind the connection gate.
  bool get needsServer => true;

  @override
  bool operator ==(Object other) =>
      other is AppRoute && other.runtimeType == runtimeType && other.arg == arg;

  @override
  int get hashCode => Object.hash(runtimeType, arg);
}

class WorkspacesRoute extends AppRoute {
  const WorkspacesRoute() : super('workspaces');
}

class WorkspaceRoute extends AppRoute {
  const WorkspaceRoute(String slug) : super('workspaces', slug);

  String get slug => arg!;

  @override
  AppRoute get up => const WorkspacesRoute();
}

class DocumentsRoute extends AppRoute {
  const DocumentsRoute() : super('documents');
}

/// One document, by its `folder/name` path.
class DocumentRoute extends AppRoute {
  const DocumentRoute(String path) : super('documents', path);

  String get path => arg!;

  @override
  AppRoute get up => const DocumentsRoute();
}

/// Sending files to the server.
class UploadRoute extends AppRoute {
  const UploadRoute() : super('upload');
}

/// The AnythingLLM address and key.
class SettingsRoute extends AppRoute {
  const SettingsRoute() : super('settings');

  @override
  bool get needsServer => false;
}

/// One place the sidebar and the tab bar both list: its icon, its label and where it goes.
typedef NavEntry = ({String icon, String label, AppRoute route});

const navEntries = <NavEntry>[
  (icon: 'folder', label: 'Workspaces', route: WorkspacesRoute()),
  (icon: 'book', label: 'Documents', route: DocumentsRoute()),
  (icon: 'file', label: 'Upload', route: UploadRoute()),
  (icon: 'settings', label: 'Settings', route: SettingsRoute()),
];

/// The current page.
class NavController extends ChangeNotifier {
  /// Starts on [initial], or on the workspaces.
  NavController([AppRoute? initial])
    : _route = initial ?? const WorkspacesRoute();

  AppRoute _route;

  AppRoute get route => _route;

  /// The page one step up, or null on a section's own page.
  AppRoute? get parent => _route.up;

  void go(AppRoute route) {
    if (route == _route) return;
    _route = route;
    notifyListeners();
  }
}
