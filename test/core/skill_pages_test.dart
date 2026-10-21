import 'package:anywherellm/core/skill_pages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const library = '/library-lean/aB3_-x9.html';
  const vault = '/vault-lean/q9Zx_-1aB2.html';

  test('both pages are kept when the bridge names them', () {
    final pages = skillPagesOf({'library': library, 'vault': vault});
    expect(pages.library, library);
    expect(pages.vault, vault);
    expect(pages.of(SkillPage.library), library);
    expect(pages.of(SkillPage.vault), vault);
  });

  test('a page that is null is not set up', () {
    final pages = skillPagesOf({'library': null, 'vault': vault});
    expect(pages.of(SkillPage.library), isNull);
    expect(pages.of(SkillPage.vault), vault);
    expect(skillPagesOf(<String, Object?>{}).vault, isNull);
  });

  test('a value that is not a string is none', () {
    final pages = skillPagesOf({
      'library': 3,
      'vault': ['/vault-lean/a.html'],
    });
    expect(pages.library, isNull);
    expect(pages.vault, isNull);
  });

  test('an answer that is not a map names no page', () {
    for (final body in [
      null,
      'x',
      7,
      [library, vault],
    ]) {
      final pages = skillPagesOf(body);
      expect(pages.library, isNull, reason: '$body');
      expect(pages.vault, isNull, reason: '$body');
    }
  });

  test('a path in the other page\'s folder is none', () {
    final pages = skillPagesOf({'library': vault, 'vault': library});
    expect(pages.library, isNull);
    expect(pages.vault, isNull);
  });

  test('an address, or a path with a query or a dot segment, is none', () {
    for (final value in [
      'https://x/vault-lean/abc.html',
      '//x/vault-lean/abc.html',
      '/vault-lean/abc.html?next=https://x',
      '/vault-lean/abc.html#top',
      '/vault-lean/../vault-lean/abc.html',
      '/vault-lean/../x.html',
      '/vault-lean/a/b.html',
      '/vault-lean/abc.json',
      'vault-lean/abc.html',
    ]) {
      expect(skillPagesOf({'vault': value}).vault, isNull, reason: value);
    }
  });

  test('the pages are named for people', () {
    expect(SkillPage.library.title, 'Library');
    expect(SkillPage.vault.title, 'Vault');
    expect(SkillPage.library.folder, 'library-lean');
    expect(SkillPage.vault.folder, 'vault-lean');
  });
}
