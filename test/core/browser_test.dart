import 'package:anywherellm/core/browser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
