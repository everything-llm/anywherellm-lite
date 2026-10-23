import 'browser_tabs.dart';
import 'chat.dart';
import 'connection.dart';
import 'page_status.dart';

/// How the bridge's `GET /pages` lists one of the suite's pages and the toolkit's card shows it:
/// the [name] its answer keys the page by, the page's [title] for people, what it holds
/// ([about]), how a sentence names it ([called]), its row's [icon], and what sets it up when it
/// is not yet ([setUp]).
typedef PageListing = ({
  String name,
  String title,
  String about,
  String called,
  String icon,
  String setUp,
});

/// A page an agent skill publishes into AnythingLLM's web folder, `/<folder>/<token>.html`,
/// which AnythingLLM serves without a sign-in: each kind with the [folder] it lives in and the
/// [prefix] its token starts with, whether it opens in the app's theme ([themed]), in its
/// increased-contrast form too ([contrasted]), and on the
/// open workspace's section ([onWorkspace]), whether its address carries a secret the page
/// embeds ([secret]), whether it is given the apps channel for its Comment ([comments]), and,
/// for the pages the bridge knows the place of, how `GET /pages` lists it ([listing]).
enum SkillPage {
  /// browser-lean's page for an agent's tab, which the skill links its tab's card to.
  browserTab('browser-lean'),

  /// apps-lean's app manager, one page for every workspace's apps, opened on the open
  /// workspace's section (`#ws=<slug>`). It shares the app pages' folder, its token marked
  /// `manager-`, and takes no comments.
  appsManager(
    'apps-lean',
    prefix: 'manager-',
    themed: true,
    contrasted: true,
    onWorkspace: true,
    secret: true,
    listing: (
      name: 'apps',
      title: 'Apps',
      about: 'Every workspace\'s apps',
      called: 'the app manager',
      icon: 'apps',
      setUp: 'Ask the agent about your apps in a chat, then try again.',
    ),
  ),

  /// An apps-lean app's page.
  apps('apps-lean', themed: true, comments: true),

  /// library-lean's Library page, its toolkits and runs.
  library(
    'library-lean',
    secret: true,
    listing: (
      name: 'library',
      title: 'Library',
      about: 'Toolkits and runs',
      called: 'the Library',
      icon: 'grid',
      setUp: 'Ask the agent to open the Library in a chat, then try again.',
    ),
  ),

  /// The Vault, the page the skills that keep secrets share: where the person gives a service's
  /// key or OAuth client without the agent seeing it, and sees and deletes every saved key,
  /// sign-in and login.
  vault(
    'vault-lean',
    themed: true,
    contrasted: true,
    secret: true,
    listing: (
      name: 'vault',
      title: 'Vault',
      about: 'Keys, sign-ins and allowed addresses',
      called: 'the Vault',
      icon: 'shield',
      setUp: 'Ask the agent to open the Vault in a chat, then try again.',
    ),
  );

  const SkillPage(
    this.folder, {
    this.prefix = '',
    this.themed = false,
    this.contrasted = false,
    this.onWorkspace = false,
    this.secret = false,
    this.comments = false,
    this.listing,
  });

  /// The skill's folder in the web folder, the first segment of its pages' paths.
  final String folder;

  /// What the page's token starts with, which tells it from another kind in the same folder.
  final String prefix;

  /// Whether the page opens in the theme the app shows in ([pageInTheme]).
  final bool themed;

  /// Whether a [themed] page takes the increased-contrast themes as well, as the suite's own
  /// pages do; an app's page has only light and dark.
  final bool contrasted;

  /// Whether the page opens on the open workspace's section, as `#ws=<slug>`.
  final bool onWorkspace;

  /// Whether the page's address carries a secret the page embeds, so the web view keeps no copy
  /// of it.
  final bool secret;

  /// Whether the page is given the apps channel, over which it posts its Comment.
  final bool comments;

  /// How the bridge's `GET /pages` lists the page, for the Library and the Vault; null for a
  /// page it does not know the place of.
  final PageListing? listing;

  /// The address the page at [url] opens at: in the [dark] or light theme when it is [themed],
  /// with [more] contrast when it is [contrasted], and on [workspace]'s section when it opens
  /// [onWorkspace] and one is open.
  Uri openedAt(
    Uri url, {
    required bool dark,
    bool more = false,
    String? workspace,
  }) {
    final themedUrl = themed
        ? pageInTheme(url, dark: dark, more: more && contrasted)
        : url;
    return onWorkspace && workspace != null
        ? themedUrl.replace(fragment: 'ws=$workspace')
        : themedUrl;
  }
}

/// A page's path, `/<folder>/<token>.html`, with the folder and the token in its groups.
final _page = RegExp(r'^/([^/]+)/([A-Za-z0-9_-]+)\.html$');

/// The suite's page [path] is, whatever the origin: exactly `/<folder>/<token>.html` in that
/// page's folder, its token starting with the page's [SkillPage.prefix], with no host, query,
/// fragment or further segment; null for any other path. Of the kinds in one folder, the one
/// with the longest prefix the token starts with is the page, so the app manager is never read
/// as an app's page.
SkillPage? skillPageAt(String path) {
  final match = _page.firstMatch(path);
  if (match == null) return null;
  final (folder, token) = (match[1], match[2]!);
  SkillPage? found;
  for (final page in SkillPage.values) {
    if (page.folder == folder &&
        token.startsWith(page.prefix) &&
        page.prefix.length >= (found?.prefix.length ?? 0)) {
      found = page;
    }
  }
  return found;
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

/// The suite's page an answer's link [href] opens, with its address resolved on [server]
/// ([onServer]), or null when it is none ([skillPageOf]).
(SkillPage, Uri)? skillLinkOf(String href, Uri? server) {
  final link = Uri.tryParse(href.trim());
  if (link == null) return null;
  final url = onServer(link, server);
  return switch (skillPageOf(url, server)) {
    final page? => (page, url),
    null => null,
  };
}

/// Whether [page] is one of the suite's pages whose address carries the secret the page embeds
/// ([SkillPage.secret]), so the web view keeps no copy of it.
bool holdsSecret(Uri page) => skillPageAt(page.path)?.secret ?? false;

/// [page] opened in the light or dark theme, as `?theme=light` or `?theme=dark`, or with [more]
/// contrast as `?theme=light-hc` or `?theme=dark-hc`, which the skill's script reads to keep the
/// page to that theme whatever the web view's own scheme is. The rest of the address is kept,
/// and a `theme` it already had is replaced. A query that is not valid UTF-8 cannot be kept, and
/// is replaced by the theme.
Uri pageInTheme(Uri page, {required bool dark, bool more = false}) {
  Map<String, String> kept;
  try {
    kept = page.queryParameters;
  } on FormatException {
    kept = const {};
  }
  return page.replace(
    queryParameters: {
      ...kept,
      'theme': '${dark ? 'dark' : 'light'}${more ? '-hc' : ''}',
    },
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

/// A `GET /pages` answer: where the listed pages are ([paths]), the agent's browser's open tabs
/// ([tabs], null when the bridge does not say), and what it says of the pages ([status]).
class SuitePages {
  const SuitePages({
    this.paths = const {},
    this.tabs,
    this.status = const PageStatus(),
  });

  final SkillPages paths;
  final List<OpenTab>? tabs;
  final PageStatus status;

  /// What a `GET /pages` answer [body] says, answered with the server's clock [skew] ahead of
  /// the phone's ([openTabsOf]).
  static SuitePages fromJson(Object? body, {Duration? skew}) => SuitePages(
    paths: skillPagesOf(body),
    tabs: body is Map ? openTabsOf(body['browser'], skew: skew) : null,
    status: PageStatus.fromJson(body is Map ? body['status'] : null),
  );
}
