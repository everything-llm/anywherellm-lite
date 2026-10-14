import 'chat.dart';

/// The path of browser-lean's page for an agent's tab: `/browser-lean/<token>.html`, which the
/// skill links its tab's card to and AnythingLLM serves without a sign-in.
final _tabPage = RegExp(r'^/browser-lean/[A-Za-z0-9_-]+\.html$');

/// Whether [link] is browser-lean's page for an agent's tab, on [server]'s host as an answer's
/// image may be ([loadableImage]).
bool isBrowserTab(Uri link, Uri? server) =>
    loadableImage(link, server) && _tabPage.hasMatch(link.path);
