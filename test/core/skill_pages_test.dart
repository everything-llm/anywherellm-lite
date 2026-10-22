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
    expect(SkillPage.library.listing?.title, 'Library');
    expect(SkillPage.vault.listing?.title, 'Vault');
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

  group('on the server\'s origin', () {
    final server = Uri.parse('https://owen.example.ts.net:3001');
    bool tab(String link, {Uri? on}) => isBrowserTab(Uri.parse(link), on);

    test('a tab\'s page on the server\'s host is the agent\'s browser', () {
      expect(
        tab(
          'https://owen.example.ts.net:3001/browser-lean/3kQ_Zx-1.html',
          on: server,
        ),
        isTrue,
      );
    });

    test(
      'never another host, another path, plain http off home, or no server',
      () {
        expect(
          tab('https://evil.test/browser-lean/3kQ.html', on: server),
          isFalse,
        );
        expect(
          tab(
            'https://owen.example.ts.net:3001/browser-lean/3kQ-card.jpg',
            on: server,
          ),
          isFalse,
        );
        expect(
          tab(
            'https://owen.example.ts.net:3001/browser-lean/a/b.html',
            on: server,
          ),
          isFalse,
        );
        final public = Uri.parse('https://ai.example.com');
        expect(
          tab('http://ai.example.com/browser-lean/3kQ.html', on: public),
          isFalse,
        );
        expect(
          tab('https://owen.example.ts.net:3001/browser-lean/3kQ.html'),
          isFalse,
        );
      },
    );

    test('never the server\'s host on another scheme or port', () {
      final named = Uri.parse('https://nas.ts.net');
      for (final link in [
        'http://nas.ts.net:8080/vault-lean/x.html',
        'http://nas.ts.net/vault-lean/x.html',
        'https://nas.ts.net:8443/vault-lean/x.html',
      ]) {
        final url = Uri.parse(link);
        expect(isVaultPage(url, named), isFalse, reason: link);
        expect(
          isBrowserTab(Uri.parse(link.replaceAll('vault', 'browser')), named),
          isFalse,
          reason: link,
        );
        expect(
          isLibraryPage(Uri.parse(link.replaceAll('vault', 'library')), named),
          isFalse,
          reason: link,
        );
        expect(
          isAppsLeanPage(Uri.parse(link.replaceAll('vault', 'apps')), named),
          isFalse,
          reason: link,
        );
      }
      expect(
        isVaultPage(
          Uri.parse('https://nas.ts.net:443/vault-lean/x.html'),
          named,
        ),
        isTrue,
      );
      expect(
        isVaultPage(Uri.parse('https://nas.ts.net/vault-lean/x.html'), named),
        isTrue,
      );
      expect(
        isVaultPage(
          Uri.parse('https://nas.ts.net:3001/vault-lean/x.html'),
          Uri.parse('https://nas.ts.net:3001'),
        ),
        isTrue,
      );
    });

    test('the Vault is its page on the server\'s host', () {
      bool vault(String link) => isVaultPage(Uri.parse(link), server);
      expect(
        vault('https://owen.example.ts.net:3001/vault-lean/aB3_-x9.html'),
        isTrue,
      );
      expect(vault('https://evil.test/vault-lean/aB3.html'), isFalse);
      expect(
        vault('https://owen.example.ts.net:3001/library-lean/aB3.html'),
        isFalse,
      );
      expect(
        vault('https://owen.example.ts.net:3001/vault-lean/aB3-keys.json'),
        isFalse,
      );
    });

    test('the Library page is library-lean\'s page on the server\'s host', () {
      bool library(String link) => isLibraryPage(Uri.parse(link), server);
      expect(
        library('https://owen.example.ts.net:3001/library-lean/aB3_-x9.html'),
        isTrue,
      );
      expect(library('https://evil.test/library-lean/aB3.html'), isFalse);
      expect(
        library('https://owen.example.ts.net:3001/apps-lean/aB3.html'),
        isFalse,
      );
      expect(
        library('https://owen.example.ts.net:3001/library-lean/s-aB3.json'),
        isFalse,
      );
    });

    test('a skill path is exactly /<folder>/<token>.html in its folder', () {
      expect(isSkillPath('/vault-lean/aB3_-x9.html', 'vault-lean'), isTrue);
      expect(isSkillPath('/vault-lean/aB3.html', 'library-lean'), isFalse);
      expect(isSkillPath('/vault-lean/aB3.html?x=1', 'vault-lean'), isFalse);
      expect(isSkillPath('/vault-lean/../x.html', 'vault-lean'), isFalse);
      expect(
        isSkillPath('https://h/vault-lean/aB3.html', 'vault-lean'),
        isFalse,
      );
      expect(isSkillPath('/vault-lean/a/b.html', 'vault-lean'), isFalse);
    });
  });
}

/// Whether [link] is browser-lean's page for an agent's tab on [server]'s origin.
bool isBrowserTab(Uri link, Uri? server) =>
    skillPageOf(link, server) == SkillPage.browserTab;

/// Whether [link] is the Vault on [server]'s origin.
bool isVaultPage(Uri link, Uri? server) =>
    skillPageOf(link, server) == SkillPage.vault;

/// Whether [link] is the Library page on [server]'s origin.
bool isLibraryPage(Uri link, Uri? server) =>
    skillPageOf(link, server) == SkillPage.library;

/// Whether [link] is an apps-lean app's page on [server]'s origin.
bool isAppsLeanPage(Uri link, Uri? server) =>
    skillPageOf(link, server) == SkillPage.apps;

/// Whether [path] is exactly a page's path in [folder].
bool isSkillPath(String path, String folder) =>
    skillPageAt(path)?.folder == folder;
