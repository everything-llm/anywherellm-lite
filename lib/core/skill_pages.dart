import 'chat.dart';
import 'connection.dart';

/// How the bridge's `GET /pages` lists one of the suite's pages and the toolkit's card shows it:
/// the [name] its answer keys the page by, the page's [title] for people and what it holds,
/// [about].
typedef PageListing = ({String name, String title, String about});

/// A page an agent skill publishes into AnythingLLM's web folder, `/<folder>/<token>.html`,
/// which AnythingLLM serves without a sign-in: each kind with the [folder] it lives in, whether
/// it opens in the app's theme ([themed]), whether its address carries a secret the page embeds
/// ([secret]), whether it is given the apps channel for its Comment ([comments]), and, for the
/// pages the bridge knows the place of, how `GET /pages` lists it ([listing]).
enum SkillPage {
  /// browser-lean's page for an agent's tab, which the skill links its tab's card to.
  browserTab('browser-lean'),

  /// An apps-lean app's page.
  apps('apps-lean', themed: true, comments: true),

  /// library-lean's Library page, its toolkits and runs.
  library(
    'library-lean',
    secret: true,
    listing: (name: 'library', title: 'Library', about: 'Toolkits and runs'),
  ),

  /// The Vault, the page the skills that keep secrets share: where the person gives a service's
  /// key or OAuth client without the agent seeing it, and sees and deletes every saved key,
  /// sign-in and login.
  vault(
    'vault-lean',
    themed: true,
    secret: true,
    listing: (
      name: 'vault',
      title: 'Vault',
      about: 'Keys, sign-ins and allowed addresses',
    ),
  );

  const SkillPage(
    this.folder, {
    this.themed = false,
    this.secret = false,
    this.comments = false,
    this.listing,
  });

  /// The skill's folder in the web folder, the first segment of its pages' paths.
  final String folder;

  /// Whether the page opens in the theme the app shows in ([pageInTheme]).
  final bool themed;

  /// Whether the page's address carries a secret the page embeds, so the web view keeps no copy
  /// of it.
  final bool secret;

  /// Whether the page is given the apps channel, over which it posts its Comment.
  final bool comments;

  /// How the bridge's `GET /pages` lists the page, for the Library and the Vault; null for a
  /// page it does not know the place of.
  final PageListing? listing;
}

/// A page's path, `/<folder>/<token>.html`, with the folder in its one group.
final _page = RegExp(r'^/([^/]+)/[A-Za-z0-9_-]+\.html$');

/// The suite's page [path] is, whatever the origin: exactly `/<folder>/<token>.html` in that
/// page's folder, with no host, query, fragment or further segment; null for any other path.
SkillPage? skillPageAt(String path) {
  final folder = _page.firstMatch(path)?[1];
  return SkillPage.values.where((page) => page.folder == folder).firstOrNull;
}

/// The suite's page [url] is, or null when it is none: a page's path ([skillPageAt]) on
/// [server]'s own origin ([sameOrigin]) over https or over http on a private network
/// ([keySafe]), not only its host, as an answer's image may be ([loadableImage]), since another
/// port or scheme on that host is another service. A path from the root is for the caller to
/// resolve first ([onServer]).
SkillPage? skillPageOf(Uri url, Uri? server) =>
    server != null && sameOrigin(url, server) && keySafe(url)
    ? skillPageAt(url.path)
    : null;

/// Whether [page] is one of the suite's pages whose address carries the secret the page embeds
/// ([SkillPage.secret]), so the web view keeps no copy of it.
bool holdsSecret(Uri page) => skillPageAt(page.path)?.secret ?? false;

/// [page] opened in the light or dark theme, as `?theme=light` or `?theme=dark`, which the
/// skill's script reads to keep the page to that theme whatever the web view's own scheme is.
/// The rest of the address is kept, and a `theme` it already had is replaced. A query that is not
/// valid UTF-8 cannot be kept, and is replaced by the theme.
Uri pageInTheme(Uri page, {required bool dark}) {
  Map<String, String> kept;
  try {
    kept = page.queryParameters;
  } on FormatException {
    kept = const {};
  }
  return page.replace(
    queryParameters: {...kept, 'theme': dark ? 'dark' : 'light'},
  );
}

/// Where the suite's listed pages are, as the bridge's `GET /pages` said: a path from the root,
/// `/<folder>/<token>.html`, on AnythingLLM's own address, for each page set up. A path is a
/// bearer capability, since the page embeds a secret: it is opened where it is read and never
/// logged, kept or persisted.
typedef SkillPages = Map<SkillPage, String>;

/// The pages a `GET /pages` answer [body] names, each by its [SkillPage.listing]'s name. A value
/// counts only as a string that is exactly a page's path in its own folder ([skillPageAt]), so
/// an address elsewhere, a path with a query or one in another page's folder is none; anything
/// but a map names none.
SkillPages skillPagesOf(Object? body) => {
  if (body is Map)
    for (final page in SkillPage.values)
      if (page.listing case final listing?)
        if (body[listing.name] case final String path
            when skillPageAt(path) == page)
          page: path,
};
