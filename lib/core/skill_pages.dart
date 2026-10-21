import 'browser.dart';

/// One of the suite's pages the bridge knows the place of: a skill's page in AnythingLLM's web
/// folder, named as `GET /pages` names it, with the [folder] it lives in, its [title] for people
/// and what it holds, [about]. Each embeds the secret its address carries ([holdsSecret]).
enum SkillPage {
  library(libraryFolder, 'Library', 'Toolkits and runs'),
  vault(vaultFolder, 'Vault', 'Keys, sign-ins and allowed addresses');

  const SkillPage(this.folder, this.title, this.about);

  /// The skill's folder in the web folder, the first segment of its pages' paths.
  final String folder;

  /// The page's name as a person reads it.
  final String title;

  /// What the page holds, in a few words.
  final String about;
}

/// Where the suite's pages are, as the bridge's `GET /pages` said: a path from the root,
/// `/<folder>/<token>.html`, on AnythingLLM's own address, for each page set up. A path is a
/// bearer capability, since the page embeds a secret: it is opened where it is read and never
/// logged, kept or persisted.
typedef SkillPages = Map<SkillPage, String>;

/// The pages a `GET /pages` answer [body] names. A value counts only as a string that is exactly
/// a page's path in its own folder ([isSkillPath]), so an address elsewhere, a path with a query
/// or one in the other page's folder is none; anything but a map names none.
SkillPages skillPagesOf(Object? body) => {
  if (body is Map)
    for (final page in SkillPage.values)
      if (body[page.name] case final String path
          when isSkillPath(path, page.folder))
        page: path,
};

/// Whether [page] is one of the suite's pages ([SkillPage]), whose address carries the secret
/// the page embeds, so the web view keeps no copy of it.
bool holdsSecret(Uri page) =>
    SkillPage.values.any((skill) => isSkillPath(page.path, skill.folder));
