import 'package:anywherellm/core/browser.dart';
import 'package:anywherellm/core/chat.dart';
import 'package:flutter_test/flutter_test.dart';

String _call(String tool, String args) =>
    '@agent is executing `$tool` tool $args';

/// The step [thought] names, read as the stream reads it.
String? _step(String thought) => switch (toolCall(thought)) {
  final call? => browserStep(call),
  null => null,
};

final _server = Uri.parse('https://owen.example:3001');

void main() {
  chatBrowserTests();
  group('browserStep', () {
    test('names each browser skill call in words', () {
      final steps = {
        _call('browse', '{\n  "url": "https://httpbin.org/forms/post"\n}'):
            'Opening httpbin.org/forms/post',
        _call('browser-act', '{"action": "click", "ref": "e17"}'): 'Clicking',
        _call('browser-act', '{"action": "press", "text": "Enter"}'):
            'Pressing a key',
        _call('browser-act', '{"action": "select", "ref": "e3"}'):
            'Choosing an option',
        _call('browser-act', '{"action": "check", "ref": "e4"}'):
            'Ticking a box',
        _call('browser-act', '{"action": "scroll"}'): 'Scrolling',
        _call('browser-act', '{"action": "back"}'): 'Going back',
        _call('browser-act', '{"action": "reload"}'): 'Reloading the page',
        _call('browser-act', '{"action": "wait", "text": "2"}'):
            'Waiting for the page',
        _call('browser-read', '{}'): 'Reading the page',
        _call('browser-read', '{"find": "points"}'): 'Looking for "points"',
        _call('browser-read', '{"card": true}'): 'Getting the browser\'s card',
        _call('browser-handoff', '{"reason": "log in"}'):
            'Handing the browser to you',
        _call('browser-handoff', '{"done": true}'): 'Taking the browser back',
        _call('browser-login', '{"action": "ask"}'): 'Asking you for a login',
        _call('browser-login', '{"action": "code", "ref": "e2"}'):
            'Filling a 2FA code',
        _call('browser-login', '{"action": "passkey"}'):
            'Signing in with a passkey',
        _call('browser-login', '{"action": "login", "login": "l1"}'):
            'Signing in with a saved login',
      };
      steps.forEach((thought, step) => expect(_step(thought), step));
    });

    test('names the page opened by its host and path, never its query', () {
      final steps = {
        'https://news.ycombinator.com/': 'Opening news.ycombinator.com',
        'https://news.ycombinator.com/item?id=45123#c1':
            'Opening news.ycombinator.com/item',
        'https://example.org/docs/guide/': 'Opening example.org/docs/guide',
        'https://example.org/${'a' * 60}': 'Opening example.org/${'a' * 39}…',
      };
      steps.forEach(
        (url, step) => expect(_step(_call('browse', '{"url": "$url"}')), step),
      );
    });

    test('never says what is typed', () {
      final step = _step(
        _call(
          'browser-act',
          '{"action": "fill", "ref": "e1", "text": "secret"}',
        ),
      );
      expect(step, 'Typing into a field');
    });

    test('leaves other tools and other thoughts alone', () {
      expect(_step(_call('web-browsing', '{"query": "news"}')), isNull);
      expect(_step('@agent: Using SearXNG to search'), isNull);
    });

    test('says the browser is in use when the arguments do not read', () {
      expect(_step(_call('browser-act', '{not json')), 'Using the browser');
      expect(
        _step(_call('browser-act', '{"action": "zoom"}')),
        'Using the browser',
      );
      expect(_step(_call('browse', '{}')), 'Opening a page');
    });
  });

  group('browserCards', () {
    const card =
        '[![Browser: https://r.mail.example/mk/un/v2/sh/WCPx]'
        '(https://owen.example:8445/_live/browser/bw-3aeecef2b460eeb7.jpg)]'
        '(https://owen.example:8445/_live/browser/bw-3aeecef2b460eeb7)';

    test('finds a card whose description holds an address', () {
      final cards = browserCards('Card: $card', server: _server);
      expect(cards, hasLength(1));
      expect(
        cards.single.image,
        Uri.parse(
          'https://owen.example:8445/_live/browser/bw-3aeecef2b460eeb7.jpg',
        ),
      );
      expect(
        cards.single.page,
        Uri.parse(
          'https://owen.example:8445/_live/browser/bw-3aeecef2b460eeb7',
        ),
      );
      expect(
        cards.single.title,
        'Browser: https://r.mail.example/mk/un/v2/sh/WCPx',
      );
    });

    test('finds cards in order', () {
      const second =
          '[![Browser: Hacker News]'
          '(https://owen.example:8445/_live/browser/bw-0123456789abcdef.jpg)]'
          '(https://owen.example:8445/_live/browser/bw-0123456789abcdef)';
      final cards = browserCards('$card\n\nLater:\n\n$second', server: _server);
      expect(
        [for (final c in cards) c.title],
        [
          'Browser: https://r.mail.example/mk/un/v2/sh/WCPx',
          'Browser: Hacker News',
        ],
      );
    });

    test('marks a login request\'s card', () {
      final form =
          'https://owen.example:8445/_live/browser/login/lr-${'a' * 32}';
      final cards = browserCards(
        'Card: [![Log in to ycombinator.com]($form.png)]($form)',
        server: _server,
      );
      expect(cards.single.login, isTrue);
      expect(cards.single.page, Uri.parse(form));
      expect(browserCards(card, server: _server).single.login, isFalse);
    });

    test('leaves out other hosts, unlinked cards and mismatched links', () {
      const elsewhere =
          '[![Browser: x](https://other.example:8445/_live/browser/bw-3aeecef2b460eeb7.jpg)]'
          '(https://other.example:8445/_live/browser/bw-3aeecef2b460eeb7)';
      const bare =
          '![Browser: x](https://owen.example:8445/_live/browser/bw-3aeecef2b460eeb7.jpg)';
      const mismatched =
          '[![Browser: x](https://owen.example:8445/_live/browser/bw-3aeecef2b460eeb7.jpg)]'
          '(https://owen.example:8445/_live/browser/bw-0123456789abcdef)';
      expect(
        browserCards('$elsewhere\n\n$bare\n\n$mismatched', server: _server),
        isEmpty,
      );
      expect(browserCards(card, server: null), isEmpty);
    });
  });

  test('isBrowserPage tells a tab page from a login form', () {
    expect(
      isBrowserPage(
        'https://owen.example:8445/_live/browser/bw-3aeecef2b460eeb7',
        _server,
      ),
      isTrue,
    );
    expect(
      isBrowserPage(
        'https://owen.example:8445/_live/browser/login/lr-${'a' * 32}',
        _server,
      ),
      isFalse,
    );
    expect(
      isBrowserPage(
        'https://other.example:8445/_live/browser/bw-3aeecef2b460eeb7',
        _server,
      ),
      isFalse,
    );
  });
}

void chatBrowserTests() {
  const tab = {
    'card': 'https://h:8445/_live/browser/bw-3aeecef2b460eeb7.jpg',
    'page': 'https://h:8445/_live/browser/bw-3aeecef2b460eeb7',
    'frame': 'https://h:8445/_live/browser/chat/q3/budget/card.jpg',
    'state': 'user',
    'title': 'Hacker News',
    'site': 'ycombinator.com',
    'last': 'Opened the front page',
  };

  group('a chat\'s browser as the server says it', () {
    test('reads its tab and its login requests', () {
      final browser = ChatBrowser.fromJson({
        'tab': tab,
        'logins': [
          {
            'card': 'https://h:8445/_live/browser/login/lr-1.png',
            'page': 'https://h:8445/_live/browser/login/lr-1',
            'site': 'github.com',
            'state': 'saved',
          },
          {
            'card': 'https://h:8445/_live/browser/login/lr-2.png',
            'page': 'https://h:8445/_live/browser/login/lr-2',
            'site': 'github.com',
            'state': 'waiting',
          },
          {'card': 'x'},
        ],
      })!;
      expect(browser.tab!.title, 'Hacker News');
      expect(browser.tab!.site, 'ycombinator.com');
      expect(browser.tab!.yours, isTrue);
      expect(browser.tab!.says, 'You have the browser.');
      expect(browser.logins, hasLength(2));
      expect(browser.waitingLogin!.page.path, endsWith('lr-2'));
    });

    test('a chat with no tab says so, and anything else is not one', () {
      expect(ChatBrowser.fromJson({'tab': null, 'logins': []})!.tab, isNull);
      expect(ChatBrowser.fromJson('nope'), isNull);
      expect(
        ChatBrowser.fromJson({
          'tab': {'card': 'x'},
        })!.tab,
        isNull,
      );
    });

    test('a state is a sentence', () {
      expect(browserStateText('working'), 'The agent is using it.');
      expect(browserStateText('waiting'), 'The agent is waiting for you.');
      expect(browserStateText('closed'), 'The browser is closed.');
      expect(browserStateText('odd'), 'The browser is odd.');
    });
  });
}
