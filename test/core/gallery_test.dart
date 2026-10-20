import 'package:anywherellm/core/gallery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a =
      '[![Unit by a wall](https://h:3001/p/a.jpg)](https://one.example/a)';
  const b = '[![On a bracket](https://h:3001/p/b.jpg)](https://two.example/b)';

  test('two pictures on lines of their own are a gallery between the text', () {
    final parts = answerParts(
      'These are from the pages I read.\n\n$a\n\n$b\n\nThat is all.',
    );
    expect(parts, hasLength(3));
    expect(
      (parts[0] as TextPart).markdown,
      'These are from the pages I read.\n',
    );
    final pictures = (parts[1] as GalleryPart).pictures;
    expect(pictures.map((p) => p.caption), ['Unit by a wall', 'On a bracket']);
    expect(pictures.first.site, 'one.example');
    expect(pictures.first.page, Uri.parse('https://one.example/a'));
    expect(pictures.first.fileName, 'a.jpg');
    expect((parts[2] as TextPart).markdown, '\nThat is all.');
  });

  test('pictures side by side on one line, and plain images, count too', () {
    final parts = answerParts(
      '![x](https://h/p/1.png) ![y](https://h/p/2.png)',
    );
    expect((parts.single as GalleryPart).pictures.map((p) => p.site), [
      'h',
      'h',
    ]);
  });

  test('a picture on the server has its page on the server too', () {
    final server = Uri.parse('https://h.example:3001');
    final picture = Picture(
      Uri.parse('/pics/a.png'),
      page: Uri.parse('/browser-lean/t.html'),
    ).on(server);
    expect(picture.image, Uri.parse('https://h.example:3001/pics/a.png'));
    expect(
      picture.page,
      Uri.parse('https://h.example:3001/browser-lean/t.html'),
    );
    expect(picture.site, 'h.example');
    expect(
      Picture(
        Uri.parse('/pics/a.png'),
        page: Uri.parse('https://one.example/a'),
      ).on(server).page,
      Uri.parse('https://one.example/a'),
    );
    expect(Picture(Uri.parse('/a.png')).on(server).page, isNull);
  });

  test('one picture, a picture in a sentence or in code stays text', () {
    for (final text in [a, 'See $a and $b', '```\n$a\n$b\n```']) {
      expect(answerParts(text), [isA<TextPart>()], reason: text);
    }
  });
}
