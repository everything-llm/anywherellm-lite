import 'package:flutter/widgets.dart';

import '../state/nav_controller.dart';
import 'inbox_page.dart';
import 'overview_page.dart';
import 'research_pages.dart';
import 'settings_page.dart';
import 'skills_pages.dart';

/// The page for [route].
Widget pageFor(AppRoute route) => switch (route) {
  OverviewRoute() => const OverviewPage(),
  ResearchListRoute() => const ResearchListPage(),
  ResearchDocRoute(:final path) => ResearchDocPage(path),
  SkillsListRoute() => const SkillsListPage(),
  SkillDocRoute(:final name) => SkillDocPage(name),
  InboxRoute() => const InboxPage(),
  SettingsRoute() => const SettingsPage(),
};
