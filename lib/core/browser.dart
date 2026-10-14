import 'connection.dart';

/// The path of browser-lean's page for an agent's tab: `/browser-lean/<token>.html`, which the
/// skill links its tab's card to and AnythingLLM serves without a sign-in.
final _tabPage = RegExp(r'^/browser-lean/[A-Za-z0-9_-]+\.html$');

/// [link] when it is browser-lean's page for an agent's tab on [server]'s host, over https or
/// on a private network ([keySafe]); otherwise null.
Uri? browserTabOf(Uri link, Uri? server) =>
    server != null &&
        link.host == server.host &&
        keySafe(link) &&
        _tabPage.hasMatch(link.path)
    ? link
    : null;
