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

  test('the app manager is its own page in the apps folder', () {
    const manager = '/apps-lean/manager-q9Zx_-1aB2c3D4e5F6g7H8i9.html';
    expect(skillPageAt(manager), SkillPage.appsManager);
    expect(
      skillPageAt('/apps-lean/q9Zx_-1aB2c3D4e5F6g7H8i9.html'),
      SkillPage.apps,
    );
    expect(SkillPage.appsManager.comments, isFalse);
    expect(holdsSecret(Uri.parse('https://h:3001$manager')), isTrue);
    expect(skillPagesOf({'apps': manager}), {SkillPage.appsManager: manager});
    expect(
      skillPagesOf({'apps': '/apps-lean/q9Zx_-1aB2c3D4e5F6g7H8i9.html'}),
      isEmpty,
      reason: 'an app\'s own page is not the manager',
    );
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

    test('a tab\'s page on the server\'s host is the agent\'s browser', () {
      expect(
        _at(
          'https://owen.example.ts.net:3001/browser-lean/3kQ_Zx-1.html',
          on: server,
        ),
        SkillPage.browserTab,
      );
    });

    test(
      'never another host, another path, plain http off home, or no server',
      () {
        for (final (link, on) in [
          ('https://evil.test/browser-lean/3kQ.html', server),
          (
            'https://owen.example.ts.net:3001/browser-lean/3kQ-card.jpg',
            server,
          ),
          ('https://owen.example.ts.net:3001/browser-lean/a/b.html', server),
          (
            'http://ai.example.com/browser-lean/3kQ.html',
            Uri.parse('https://ai.example.com'),
          ),
          ('https://owen.example.ts.net:3001/browser-lean/3kQ.html', null),
        ]) {
          expect(_at(link, on: on), isNull, reason: link);
        }
      },
    );

    test('never the server\'s host on another scheme or port', () {
      final named = Uri.parse('https://nas.ts.net');
      for (final origin in [
        'http://nas.ts.net:8080',
        'http://nas.ts.net',
        'https://nas.ts.net:8443',
      ]) {
        for (final page in SkillPage.values) {
          final link = '$origin/${page.folder}/${page.prefix}x.html';
          expect(_at(link, on: named), isNull, reason: link);
        }
      }
      expect(
        _at('https://nas.ts.net:443/vault-lean/x.html', on: named),
        SkillPage.vault,
      );
      expect(
        _at('https://nas.ts.net/vault-lean/x.html', on: named),
        SkillPage.vault,
      );
      expect(
        _at(
          'https://nas.ts.net:3001/vault-lean/x.html',
          on: Uri.parse('https://nas.ts.net:3001'),
        ),
        SkillPage.vault,
      );
    });

    test('each page is its own folder\'s page, and nothing else is', () {
      for (final (path, page) in [
        ('/vault-lean/aB3_-x9.html', SkillPage.vault),
        ('/library-lean/aB3_-x9.html', SkillPage.library),
        ('/apps-lean/aB3.html', SkillPage.apps),
      ]) {
        expect(
          _at('https://owen.example.ts.net:3001$path', on: server),
          page,
          reason: path,
        );
        expect(_at('https://evil.test$path', on: server), isNull);
      }
      for (final path in [
        '/vault-lean/aB3-keys.json',
        '/library-lean/s-aB3.json',
      ]) {
        expect(
          _at('https://owen.example.ts.net:3001$path', on: server),
          isNull,
          reason: path,
        );
      }
    });

    test('a skill path is exactly /<folder>/<token>.html', () {
      expect(skillPageAt('/vault-lean/aB3_-x9.html'), SkillPage.vault);
      for (final path in [
        '/vault-lean/aB3.html?x=1',
        '/vault-lean/../x.html',
        'https://h/vault-lean/aB3.html',
        '/vault-lean/a/b.html',
        '/other-lean/aB3.html',
      ]) {
        expect(skillPageAt(path), isNull, reason: path);
      }
    });
  });
}

/// The suite's page [link] is on [on]'s origin ([skillPageOf]).
SkillPage? _at(String link, {Uri? on}) => skillPageOf(Uri.parse(link), on);
