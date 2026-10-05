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

  @override
  bool operator ==(Object other) =>
      other is AppRoute && other.runtimeType == runtimeType && other.arg == arg;

  @override
  int get hashCode => Object.hash(runtimeType, arg);
}

/// What the libraries hold, what their last check found, and where nils keeps things.
class OverviewRoute extends AppRoute {
  const OverviewRoute() : super('overview');
}

class ResearchListRoute extends AppRoute {
  const ResearchListRoute() : super('research');
}

class ResearchDocRoute extends AppRoute {
  const ResearchDocRoute(String path) : super('research', path);

  String get path => arg!;

  @override
  AppRoute get up => const ResearchListRoute();
}

class SkillsListRoute extends AppRoute {
  const SkillsListRoute() : super('skills');
}

class SkillDocRoute extends AppRoute {
  const SkillDocRoute(String name) : super('skills', name);

  String get name => arg!;

  @override
  AppRoute get up => const SkillsListRoute();
}

/// The files staged for adding, and the way to stage more.
class InboxRoute extends AppRoute {
  const InboxRoute() : super('inbox');
}

/// The AnythingLLM address and key.
class SettingsRoute extends AppRoute {
  const SettingsRoute() : super('settings');
}

/// One place the sidebar and the tab bar both list: its icon, its label and where it goes, and
/// the library whose findings its badge counts, when it is one.
typedef NavEntry = ({
  String icon,
  String label,
  AppRoute route,
  String? library,
});

const navEntries = <NavEntry>[
  (icon: 'folder', label: 'Overview', route: OverviewRoute(), library: null),
  (
    icon: 'book',
    label: 'Research',
    route: ResearchListRoute(),
    library: 'research',
  ),
  (icon: 'tool', label: 'Skills', route: SkillsListRoute(), library: 'skills'),
  (icon: 'file', label: 'Inbox', route: InboxRoute(), library: null),
  (icon: 'settings', label: 'Settings', route: SettingsRoute(), library: null),
];

/// The current page.
class NavController extends ChangeNotifier {
  /// Starts on [initial], or on the overview.
  NavController([AppRoute? initial])
    : _route = initial ?? const OverviewRoute();

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
