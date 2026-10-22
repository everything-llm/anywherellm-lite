import 'package:anywherellm/core/apps_lean.dart';
import 'package:anywherellm/core/markdown.dart';
import 'package:anywherellm/core/skill_pages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  final server = Uri.parse('https://owen.example.ts.net:3001');
  bool page(String link, {Uri? on}) =>
      skillPageOf(Uri.parse(link), on) == SkillPage.apps;

  test(
    'a page opens in the light or dark theme, keeping the rest of its address',
    () {
      final page = Uri.parse(
        'https://owen.example.ts.net:3001/apps-lean/q9Z.html',
      );
      expect(
        pageInTheme(page, dark: false).toString(),
        'https://owen.example.ts.net:3001/apps-lean/q9Z.html?theme=light',
      );
      expect(
        pageInTheme(
          page.replace(query: 'tab=2&theme=light'),
          dark: true,
        ).queryParameters,
        {'tab': '2', 'theme': 'dark'},
      );
      expect(
        skillPageOf(pageInTheme(page, dark: true), server),
        SkillPage.apps,
      );
    },
  );

  test('a query that is not valid UTF-8 is replaced by the theme', () {
    final page = Uri.parse(
      'https://owen.example.ts.net:3001/apps-lean/a.html?x=%ff',
    );
    expect(
      pageInTheme(page, dark: true).toString(),
      'https://owen.example.ts.net:3001/apps-lean/a.html?theme=dark',
    );
  });

  test('an app\'s page on the server\'s host is an apps-lean page', () {
    expect(
      page(
        'https://owen.example.ts.net:3001/apps-lean/q9Zx_-1aB2c3D4e5F6g7H8i9.html',
        on: server,
      ),
      isTrue,
    );
  });

  test(
    'never another host, another path, plain http off home, or no server',
    () {
      expect(page('https://evil.test/apps-lean/q9Z.html', on: server), isFalse);
      expect(
        page('https://owen.example.ts.net:3001/apps-lean/a/b.html', on: server),
        isFalse,
      );
      expect(
        page('https://owen.example.ts.net:3001/_apps/fonts/x.html', on: server),
        isFalse,
      );
      final public = Uri.parse('https://ai.example.com');
      expect(
        page('http://ai.example.com/apps-lean/q9Z.html', on: public),
        isFalse,
      );
      expect(
        page('https://owen.example.ts.net:3001/apps-lean/q9Z.html'),
        isFalse,
      );
    },
  );

  group('an app\'s card', () {
    AppCard? card(String text) =>
        parseAnswer(text)
            .whereType<md.Element>()
            .map((e) => appCardOf(e, server))
            .firstWhere((c) => c != null, orElse: () => null);

    test('is a quote that opens with a link to the app\'s page', () {
      final c = card(
        '> [**Groceries**](/apps-lean/q9Z.html)\n> Added Oat milk and Coffee',
      )!;
      expect(c.title, 'Groceries');
      expect(c.href, '/apps-lean/q9Z.html');
      expect(c.lines, ['Added Oat milk and Coffee']);
    });

    test(
      'may hold the link in bold, a title alone, or lines in more blocks',
      () {
        expect(card('> **[Groceries](/apps-lean/q9Z.html)**')!.lines, isEmpty);
        final c = card(
          '> [Groceries](/apps-lean/q9Z.html)\n>\n> - Ticked off Eggs\n> - Added Tea',
        )!;
        expect(c.lines, ['Ticked off Eggs', 'Added Tea']);
      },
    );

    test('is also a paragraph that opens with the link', () {
      final c = card('[Groceries](/apps-lean/q9Z.html) - Added Tea')!;
      expect(c.title, 'Groceries');
      expect(c.lines, ['Added Tea']);
      expect(card('**[Groceries](/apps-lean/q9Z.html)**')!.lines, isEmpty);
    });

    test('is not a list item that opens with the link', () {
      bool holdsCard(List<md.Node> nodes) => nodes.any(
        (n) =>
            n is md.Element &&
            (n.tag == appCardTag || holdsCard(n.children ?? const [])),
      );
      expect(
        holdsCard(
          parseAnswer('- [Groceries](/apps-lean/q9Z.html) - Added Tea'),
        ),
        isFalse,
      );
      expect(
        holdsCard(parseAnswer('[Groceries](/apps-lean/q9Z.html) - Added Tea')),
        isTrue,
      );
    });

    test('is not any other quote, nor a link in a paragraph', () {
      expect(card('> Groceries: [open](/apps-lean/q9Z.html)'), isNull);
      expect(card('> [Docs](https://evil.test/apps-lean/q9Z.html)'), isNull);
      expect(card('> [Docs](/browser-lean/q9Z.html)'), isNull);
      expect(card('Made it: [Groceries](/apps-lean/q9Z.html)'), isNull);
    });
  });

  group('a comment from a page', () {
    test('is the page\'s message, trimmed, for the app\'s workspace', () {
      expect(
        pageCommentOf({
          'comment': {'workspace': 'home', 'message': ' Why? '},
        }),
        (workspace: 'home', message: 'Why?'),
      );
    });

    test('is cut to its longest', () {
      final comment = pageCommentOf({
        'comment': {'workspace': 'home', 'message': 'x' * 5000},
      });
      expect(comment?.message.length, commentMax);
    });

    test('is none without a message or a workspace', () {
      expect(
        pageCommentOf({
          'comment': {'workspace': 'home', 'message': '  '},
        }),
        isNull,
      );
      expect(
        pageCommentOf({
          'comment': {'message': 'Why?'},
        }),
        isNull,
      );
      expect(pageCommentOf('Why?'), isNull);
    });
  });
}
