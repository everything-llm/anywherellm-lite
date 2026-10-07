import 'package:anywherellm/core/markdown.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
