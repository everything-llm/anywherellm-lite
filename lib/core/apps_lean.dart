import 'browser.dart';

/// Whether [link] is an apps-lean app's page: `/apps-lean/<token>.html`, which the skill
/// publishes into AnythingLLM's web folder.
bool isAppsLeanPage(Uri link, Uri? server) =>
    isSkillPage(link, server, 'apps-lean');
