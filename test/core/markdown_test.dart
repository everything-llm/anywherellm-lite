import 'package:anywherellm/core/markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

/// The everythingllm browser's card for a page without a title, as an agent pasted it.
const _card =
    'Card: [![Browser: https://r.mail.recraft.ai/mk/un/v2/sh/WCPx/fqEYtNipp1Pg]'
    '(https://owen.example:8445/_live/browser/bw-3aeecef2b460eeb7.jpg)]'
    '(https://owen.example:8445/_live/browser/bw-3aeecef2b460eeb7)';

/// The elements of the one paragraph [text] is, as an answer is parsed.
List<md.Element> _inline(String text) =>
    (parseAnswer(text).single as md.Element).children!
        .whereType<md.Element>()
        .toList();

void main() {
  test('an answer is read as words, without its markup', () {
    expect(
      plainText(
        '## Budget\n\nAbout **40k**, see [the plan](https://x.example).\n\n'
        '- rent\n- food',
      ),
      'Budget\nAbout 40k, see the plan.\nrent\nfood',
    );
  });

  test('a table is read a row to a line, its cells apart', () {
    expect(
      plainText('| Name | Age |\n| --- | --- |\n| Ann | 31 |\n| Bo |  |'),
      'Name, Age\nAnn, 31\nBo',
    );
  });

  test('a list item with markup in it is read as one line', () {
    expect(
      plainText('- pay **rent** first\n- then food\n  - nested *item*'),
      'pay rent first\nthen food\nnested item',
    );
  });

  test("an address in a card's description leaves the card whole", () {
    final link = _inline(_card).single;
    expect(link.tag, 'a');
    expect(
      link.attributes['href'],
      'https://owen.example:8445/_live/browser/bw-3aeecef2b460eeb7',
    );
    final image = link.children!.whereType<md.Element>().single;
    expect(image.tag, 'img');
    expect(
      image.attributes['src'],
      'https://owen.example:8445/_live/browser/bw-3aeecef2b460eeb7.jpg',
    );
    expect(
      image.attributes['alt'],
      'Browser: https://r.mail.recraft.ai/mk/un/v2/sh/WCPx/fqEYtNipp1Pg',
    );
  });

  test('a bare address in the text is still a link', () {
    expect(
      [
        for (final a in _inline(
          'See https://x.example/a_(b) and (www.y.example).',
        ))
          a.attributes['href'],
      ],
      ['https://x.example/a_(b)', 'http://www.y.example'],
    );
  });

  test('an answer is read with its characters, not their HTML escapes', () {
    expect(plainText('Tom & Jerry <3 "cheese"'), 'Tom & Jerry <3 "cheese"');
  });

  test('TeX is read as its source, as math rather than as emphasis', () {
    expect(plainText(r'Here $a_i + b_i$ holds.'), r'Here a_i + b_i holds.');
  });

  test('a bare address keeps the brackets it opens and closes', () {
    expect(
      [
        for (final a in _inline(
          'See https://x.example/?ids[]=1&f[name]=a [see https://y.example/b] '
          'and https://z.example/a[b[c]].',
        ))
          a.textContent,
      ],
      [
        'https://x.example/?ids[]=1&f[name]=a',
        'https://y.example/b',
        'https://z.example/a[b[c]]',
      ],
    );
  });
}
