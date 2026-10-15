import 'package:anywherellm/core/apps_lean.dart';
import 'package:anywherellm/core/markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  final server = Uri.parse('https://owen.example.ts.net:3001');
  bool page(String link, {Uri? on}) => isAppsLeanPage(Uri.parse(link), on);

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

    test('is not any other quote, nor a link in a paragraph', () {
      expect(card('> Groceries: [open](/apps-lean/q9Z.html)'), isNull);
      expect(card('> [Docs](https://evil.test/apps-lean/q9Z.html)'), isNull);
      expect(card('> [Docs](/browser-lean/q9Z.html)'), isNull);
      expect(card('Made it: [Groceries](/apps-lean/q9Z.html)'), isNull);
    });
  });
}
