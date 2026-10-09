import 'package:anywherellm/core/browser.dart';
import 'package:anywherellm/core/host_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final server = Uri.parse('https://host.example.ts.net:3001');

  test('a live route is on the cards port under /_live', () {
    expect(
      liveRoute(server, 'sandbox/files/q3').toString(),
      'https://host.example.ts.net:8445/_live/sandbox/files/q3',
    );
    expect(
      liveRoute(server, 'x', {'a': 'b c'}).toString(),
      'https://host.example.ts.net:8445/_live/x?a=b+c',
    );
  });

  test('the browser\'s route has the chat encoded, a tail and a query', () {
    expect(
      browserRoute(server, 'q 3', 'a/b', '/card.jpg', {
        'theme': 'light',
      }).toString(),
      'https://host.example.ts.net:8445/_live/browser/chat/q%203/a%2Fb/card.jpg'
      '?theme=light',
    );
  });
}
