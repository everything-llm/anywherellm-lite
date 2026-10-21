import 'package:anywherellm/core/skill_pages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const library = '/library-lean/aB3_-x9.html';
  const vault = '/vault-lean/q9Zx_-1aB2.html';

  test('both pages are kept when the bridge names them', () {
    expect(skillPagesOf({'library': library, 'vault': vault}), {
      SkillPage.library: library,
      SkillPage.vault: vault,
    });
  });

  test('a page that is null is not set up', () {
    expect(skillPagesOf({'library': null, 'vault': vault}), {
      SkillPage.vault: vault,
    });
    expect(skillPagesOf(<String, Object?>{}), isEmpty);
  });

  test('a value that is not a string is none', () {
    expect(
      skillPagesOf({
        'library': 3,
        'vault': ['/vault-lean/a.html'],
      }),
      isEmpty,
    );
  });

  test('an answer that is not a map names no page', () {
    for (final body in [
      null,
      'x',
      7,
      [library, vault],
    ]) {
      expect(skillPagesOf(body), isEmpty, reason: '$body');
    }
  });

  test('a path in the other page\'s folder is none', () {
    expect(skillPagesOf({'library': vault, 'vault': library}), isEmpty);
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
      expect(skillPagesOf({'vault': value}), isEmpty, reason: value);
    }
  });

  test('the pages are named for people', () {
    expect(SkillPage.library.title, 'Library');
    expect(SkillPage.vault.title, 'Vault');
    expect(SkillPage.library.folder, 'library-lean');
    expect(SkillPage.vault.folder, 'vault-lean');
  });

  test('only the Vault and the Library hold a secret in their address', () {
    bool holds(String link) => holdsSecret(Uri.parse(link));
    expect(holds('https://h:3001/vault-lean/aB3.html'), isTrue);
    expect(holds('https://h:3001/vault-lean/aB3.html?theme=dark'), isTrue);
    expect(holds('/library-lean/aB3.html'), isTrue);
    expect(holds('https://h:3001/apps-lean/aB3.html'), isFalse);
    expect(holds('https://h:3001/browser-lean/aB3.html'), isFalse);
    expect(holds('https://h:3001/vault-lean/aB3.json'), isFalse);
  });
}
