import 'chat.dart';

/// Whether [link] is the page `/<folder>/<token>.html` of an agent skill that publishes into
/// AnythingLLM's web folder, which AnythingLLM serves without a sign-in, on [server]'s own origin:
/// its scheme, host and port, not only its host as an answer's image may be ([loadableImage]),
/// since another port or scheme on that host is another service. A path from the root is for the
/// caller to resolve first ([onServer]).
bool isSkillPage(Uri link, Uri? server, String folder) =>
    server != null &&
    link.scheme == server.scheme &&
    link.port == server.port &&
    loadableImage(link, server) &&
    isSkillPath(link.path, folder);

/// A page's path, `/<folder>/<token>.html`, with the folder in its one group.
final _page = RegExp(r'^/([^/]+)/[A-Za-z0-9_-]+\.html$');

/// Whether [path] is exactly `/<folder>/<token>.html`, a page of that skill's folder: no host,
/// query, fragment or further segment.
bool isSkillPath(String path, String folder) =>
    _page.firstMatch(path)?[1] == folder;

/// library-lean's folder, which holds its Library page.
const libraryFolder = 'library-lean';

/// vault-lean's folder, which holds the Vault.
const vaultFolder = 'vault-lean';

/// Whether [link] is browser-lean's page for an agent's tab: `/browser-lean/<token>.html`, which
/// the skill links its tab's card to.
bool isBrowserTab(Uri link, Uri? server) =>
    isSkillPage(link, server, 'browser-lean');

/// Whether [link] is library-lean's Library page, `/library-lean/<token>.html`, its toolkits and
/// runs.
bool isLibraryPage(Uri link, Uri? server) =>
    isSkillPage(link, server, libraryFolder);

/// Whether [link] is the Vault, `/vault-lean/<token>.html`, the page the skills that keep secrets
/// share: where the person gives a service's key or OAuth client without the agent seeing it, and
/// sees and deletes every saved key, sign-in and login.
bool isVaultPage(Uri link, Uri? server) =>
    isSkillPage(link, server, vaultFolder);
