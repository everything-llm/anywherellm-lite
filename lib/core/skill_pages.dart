import 'browser.dart';

/// One of the suite's pages the bridge knows the place of: a skill's page in AnythingLLM's web
/// folder, with the [folder] it lives in and its [title] for people.
enum SkillPage {
  library('library-lean', 'Library'),
  vault('vault-lean', 'Vault');

  const SkillPage(this.folder, this.title);

  /// The skill's folder in the web folder, the first segment of its pages' paths.
  final String folder;

  /// The page's name as a person reads it.
  final String title;
}

/// Where the suite's pages are, as the bridge's `GET /pages` said: a path from the root,
/// `/<folder>/<token>.html`, on AnythingLLM's own address, or null for a page not set up. A path
/// is a bearer capability, since the page embeds a secret: it is opened where it is read and
/// never logged, kept or persisted.
class SkillPages {
  const SkillPages({this.library, this.vault});

  final String? library;
  final String? vault;

  /// Where [page] is, or null when it is not set up.
  String? of(SkillPage page) => switch (page) {
    SkillPage.library => library,
    SkillPage.vault => vault,
  };
}

/// The pages a `GET /pages` answer [body] names. A value counts only as a string that is exactly
/// a page's path in its own folder ([isSkillPath]), so an address elsewhere, a path with a query
/// or one in the other page's folder is none; anything but a map names none.
SkillPages skillPagesOf(Object? body) {
  String? path(SkillPage page) {
    final value = body is Map ? body[page.name] : null;
    return value is String && isSkillPath(value, page.folder) ? value : null;
  }

  return SkillPages(
    library: path(SkillPage.library),
    vault: path(SkillPage.vault),
  );
}
