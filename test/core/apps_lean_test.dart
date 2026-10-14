import 'package:anywherellm/core/apps_lean.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
