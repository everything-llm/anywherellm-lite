import 'package:anywherellm/core/markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

/// The everythingllm browser's card for a page without a title, as an agent pasted it.
const _card =
    'Card: [![Browser: https://r.mail.recraft.ai/mk/un/v2/sh/WCPx/fqEYtNipp1Pg]'
    '(https://owen.example:8445/_live/browser/bw-3aeecef2b460eeb7.jpg)]'
    '(https://owen.example:8445/_live/browser/bw-3aeecef2b460eeb7)';

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

  test('a list item with markup in it is read as one line', () {
    expect(
      plainText('- pay **rent** first\n- then food\n  - nested *item*'),
      'pay rent first\nthen food\nnested item',
    );
  });

  test("an address in a card's description leaves the card whole", () {
    final p = md.Document(extensionSet: answerMarkdown).parse(_card).single;
    final link = (p as md.Element).children!.whereType<md.Element>().single;
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
    final p = md.Document(extensionSet: answerMarkdown)
        .parse('See https://x.example/a_(b) and (www.y.example).')
        .single;
    final links = (p as md.Element).children!.whereType<md.Element>();
    expect(
      [for (final a in links) a.attributes['href']],
      ['https://x.example/a_(b)', 'http://www.y.example'],
    );
  });

  test('an answer is read with its characters, not their HTML escapes', () {
    expect(plainText('Tom & Jerry <3 "cheese"'), 'Tom & Jerry <3 "cheese"');
  });

  test('a bare address keeps the brackets it opens and closes', () {
    final p = md.Document(extensionSet: answerMarkdown, encodeHtml: false)
        .parse(
          'See https://x.example/?ids[]=1&f[name]=a [see https://y.example/b].',
        )
        .single;
    final links = (p as md.Element).children!.whereType<md.Element>();
    expect(
      [for (final a in links) a.textContent],
      ['https://x.example/?ids[]=1&f[name]=a', 'https://y.example/b'],
    );
  });
}
