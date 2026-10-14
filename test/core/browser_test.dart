import 'package:anywherellm/core/browser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final server = Uri.parse('https://owen.example.ts.net:3001');
  Uri? tab(String link, {Uri? on}) => browserTabOf(Uri.parse(link), on);

  test('a tab\'s page on the server\'s host is the agent\'s browser', () {
    expect(
      tab(
        'https://owen.example.ts.net:3001/browser-lean/3kQ_Zx-1.html',
        on: server,
      ),
      isNotNull,
    );
  });

  test(
    'never another host, another path, plain http off home, or no server',
    () {
      expect(
        tab('https://evil.test/browser-lean/3kQ.html', on: server),
        isNull,
      );
      expect(
        tab(
          'https://owen.example.ts.net:3001/browser-lean/3kQ-card.jpg',
          on: server,
        ),
        isNull,
      );
      expect(
        tab(
          'https://owen.example.ts.net:3001/browser-lean/a/b.html',
          on: server,
        ),
        isNull,
      );
      final public = Uri.parse('https://ai.example.com');
      expect(
        tab('http://ai.example.com/browser-lean/3kQ.html', on: public),
        isNull,
      );
      expect(
        tab('https://owen.example.ts.net:3001/browser-lean/3kQ.html'),
        isNull,
      );
    },
  );
}
