import 'chat.dart';

/// Whether [link] is the page `/<folder>/<token>.html` of an agent skill that publishes into
/// AnythingLLM's web folder, which AnythingLLM serves without a sign-in, on [server]'s host as an
/// answer's image may be ([loadableImage]).
bool isSkillPage(Uri link, Uri? server, String folder) =>
    loadableImage(link, server) &&
    RegExp('^/$folder/[A-Za-z0-9_-]+\\.html\$').hasMatch(link.path);

/// Whether [link] is browser-lean's page for an agent's tab: `/browser-lean/<token>.html`, which
/// the skill links its tab's card to.
bool isBrowserTab(Uri link, Uri? server) =>
    isSkillPage(link, server, 'browser-lean');
