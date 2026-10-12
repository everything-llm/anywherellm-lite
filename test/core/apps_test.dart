import 'package:anywherellm/core/apps.dart';
import 'package:flutter_test/flutter_test.dart';

final _server = Uri.parse('https://h.example.ts.net:3001');

void main() {
  group('the apps server', () {
    test('is told apart by its health answer', () {
      expect(
        isAppsHealth({
          'service': 'anythingllm-apps-v2',
          'server': 'cards',
          'ok': true,
        }),
        isTrue,
      );
      expect(isAppsHealth({'service': 'everythingllm'}), isFalse);
      expect(isAppsHealth('<html>'), isFalse);
      expect(isAppsHealth(null), isFalse);
    });

    test('sits on the same host at 8466, over https', () {
      expect(
        appsBase(Uri.parse('http://h.example.ts.net:3001')).toString(),
        'https://h.example.ts.net:8466',
      );
    });
  });

  group('an app is found', () {
    test('by its card on the apps server', () {
      expect(
        appCardRef(
          Uri.parse('https://h.example.ts.net:8466/cards/home/groceries.png'),
          _server,
        ),
        const AppRef('home', 'groceries'),
      );
    });

    test('by its page, with or without its slash', () {
      for (final page in [
        'https://h.example.ts.net:8465/home/groceries/',
        'https://h.example.ts.net:8465/home/groceries',
        'https://h.example.ts.net:8465/home/groceries/?theme=dark',
      ]) {
        expect(
          appPageRef(Uri.parse(page), _server),
          const AppRef('home', 'groceries'),
          reason: page,
        );
      }
    });

    test('never on another host, port or scheme, or by another path', () {
      for (final url in [
        'https://elsewhere.example:8466/cards/home/groceries.png',
        'http://h.example.ts.net:8466/cards/home/groceries.png',
        'https://h.example.ts.net:8445/cards/home/groceries.png',
        'https://h.example.ts.net:8466/cards/home/groceries.jpg',
        'https://h.example.ts.net:8466/cards/home/Groceries.png',
        'https://h.example.ts.net:8466/apps/home',
        'https://h.example.ts.net:8465/home/groceries/extra',
      ]) {
        expect(appRefOf(Uri.parse(url), _server), isNull, reason: url);
      }
      expect(
        appRefOf(
          Uri.parse('https://h.example.ts.net:8466/cards/home/groceries.png'),
          null,
        ),
        isNull,
      );
    });
  });

  test('a card is read once, light or dark', () {
    final card = Uri.parse(
      'https://h.example.ts.net:8466/cards/home/groceries.png',
    );
    expect(onceCard(card, light: true).query, 'once=1&theme=light');
    expect(onceCard(card, light: false).query, 'once=1');
  });

  test('a page keeps to the theme it is given', () {
    final page = Uri.parse('https://h.example.ts.net:8465/home/groceries/');
    expect(
      themedPage(page, dark: true).toString(),
      'https://h.example.ts.net:8465/home/groceries/?theme=dark',
    );
    expect(
      themedPage(Uri.parse('$page?theme=dark'), dark: false).query,
      'theme=light',
    );
    expect(
      appPage(_server, const AppRef('home', 'groceries')).toString(),
      'https://h.example.ts.net:8465/home/groceries/',
    );
  });

  group('the app list', () {
    test('reads each app, newest change first', () {
      final apps = appsOf('home', {
        'apps': [
          {
            'id': 'apps/groceries',
            'name': 'groceries',
            'title': 'Groceries',
            'kind': 'list',
            'summary': '1 of 2 left',
            'modified': 1791792843.0,
            'line': 7,
            'page': 'https://h:8465/home/groceries/',
            'card': 'https://h:8466/cards/home/groceries.png',
            'link': 'https://h:8465/home/groceries/',
            'error': null,
          },
          {
            'name': 'focus',
            'title': 'Focus',
            'kind': 'pomodoro',
            'summary': '',
            'modified': 1791800000.0,
            'line': 2,
          },
          {'name': 'Not An App'},
          'nonsense',
        ],
      });
      expect([for (final app in apps) app.ref.name], ['focus', 'groceries']);
      final groceries = apps[1];
      expect(groceries.title, 'Groceries');
      expect(groceries.line, 7);
      expect(groceries.page.toString(), 'https://h:8465/home/groceries/');
      expect(
        groceries.modified,
        DateTime.fromMillisecondsSinceEpoch(1791792843000, isUtc: true),
      );
      final now = groceries.modified!.toLocal();
      expect(groceries.about(now), startsWith('List · 1 of 2 left · Today '));
      expect(apps[0].about(now), startsWith('Timer · '));
    });

    test('names an app that cannot be read by its folder, and says so', () {
      final app = ServerApp.fromJson('home', {
        'name': 'broken',
        'title': 'broken',
        'kind': null,
        'line': null,
        'summary': '',
        'error': 'app.json is not JSON',
      })!;
      expect(app.about(DateTime.now()), 'App · Cannot be read');
    });

    test('reads where the log can be put back from, and the version', () {
      final app = ServerApp.fromJson('home', {
        'name': 'groceries',
        'line': 7,
        'restorable_from': 4,
        'version': '7-5f6c11f0a2b4',
      })!;
      expect(app.restorableFrom, 4);
      expect(app.version, '7-5f6c11f0a2b4');
      final older = ServerApp.fromJson('home', {'name': 'groceries'})!;
      expect(older.restorableFrom, isNull);
      expect(older.version, isNull);
    });

    test('an app is the same by its version, or else by what it shows', () {
      ServerApp app({String? version, String title = 'Groceries'}) => ServerApp(
        ref: const AppRef('home', 'groceries'),
        title: title,
        line: 7,
        version: version,
      );
      expect(app(version: '7-aaa').sameAs(app(version: '7-aaa')), isTrue);
      // A commit changes the version though the data and title do not.
      expect(app(version: '7-aaa').sameAs(app(version: '7-bbb')), isFalse);
      // Without a version on either, what it shows decides.
      expect(app().sameAs(app(version: '7-aaa')), isTrue);
      expect(app().sameAs(app(title: 'Food')), isFalse);
    });

    test('each kind in words', () {
      expect(kindLabel('flashcards'), 'Deck');
      expect(kindLabel('pomodoro'), 'Timer');
      expect(kindLabel('habits'), 'Habits');
      expect(kindLabel(null), 'App');
    });
  });

  test('a folder lists its files by path, with sizes in words', () {
    final files = appFilesOf({
      'files': [
        {'path': 'page.html', 'size': 2400, 'modified': 1791792000.5},
        {'path': 'app.json', 'size': 812, 'modified': 1791792000.5},
      ],
    });
    expect([for (final f in files) f.path], ['app.json', 'page.html']);
    expect(bytesText(files[0].size), '812 B');
    expect(bytesText(files[1].size), '2.3 KB');
    expect(bytesText(3 * 1024 * 1024), '3.0 MB');
  });

  group('the log', () {
    const jsonl =
        '{"n":1,"t":"2026-10-12T08:00:00Z","by":"agent","ev":"made","chat":"c1",'
        '"patch":[{"op":"add","path":"","value":{"items":[]}}]}\n'
        'not json\n'
        '\n'
        '{"n":2,"t":"2026-10-12T08:14:03Z","by":"you","ev":"tick","text":"Eggs",'
        '"patch":[{"op":"replace","path":"/items/2/done","value":true}]}\n'
        '{"n":3,"t":"2026-10-12T08:20:00Z","by":"you","ev":"restore","to":1,'
        '"patch":[]}\n';

    test('reads each line, newest first, leaving out what is not one', () {
      final lines = logLinesOf(jsonl);
      expect([for (final line in lines) line.n], [3, 2, 1]);
      expect(lines[1].title, 'tick');
      expect(lines[1].by, 'you');
      expect(lines[1].detail, 'text: Eggs');
      expect(lines[0].detail, 'to: 1');
      expect(lines[2].chat, 'c1');
      expect(lines[2].detail, '');
      expect(lines[1].json['patch'], isList);
    });

    test('a page reads its lines newest first, where the log starts, and '
        'whether more remain', () {
      final page = LogPage.fromJson({
        'lines': [
          {'n': 6, 'ev': 'add'},
          {'n': 7, 'ev': 'tick'},
          'nonsense',
          {'ev': 'no number'},
        ],
        'first': 4,
        'last': 7,
        'more': true,
      });
      expect([for (final line in page.lines) line.n], [7, 6]);
      expect(page.first, 4);
      expect(page.last, 7);
      expect(page.more, isTrue);
      expect(LogPage.fromJson({}).more, isFalse);
    });

    test('a line without an event is a change', () {
      expect(LogLine.parse('{"n":4,"by":"agent","patch":[]}')!.title, 'change');
      expect(LogLine.parse('{"by":"agent"}'), isNull);
    });
  });

  test('who wrote a line, in words', () {
    expect(byText('you'), 'You');
    expect(byText('host'), 'Server');
    expect(byText(null), 'Unknown');
  });

  test('commits read newest first, with a short hash', () {
    final commits = commitsOf({
      'commits': [
        {
          'commit': '5f6c11f0a1b2c3d4e5f60718293a4b5c6d7e8f90',
          't': '2026-10-12T08:20:11Z',
          'by': 'agent',
          'chat': '8f11958e',
          'message': 'Change app.json\n',
          'files': ['app.json'],
        },
        {'commit': 42},
      ],
    });
    expect(commits, hasLength(1));
    expect(commits.single.short, '5f6c11f');
    expect(commits.single.message, 'Change app.json');
    expect(commits.single.files, ['app.json']);
  });

  test('a commit\'s title and body come from the server, or else from its '
      'message', () {
    final [split, older] = commitsOf({
      'commits': [
        {
          'commit': 'aaaa',
          'message': 'Sort ticks\n\nThey sink.',
          'subject': 'Sort ticks',
          'body': 'They sink.',
          'revertable': false,
        },
        {'commit': 'bbbb', 'message': 'Raise the goal\n\nTo 12 cards.'},
      ],
    });
    expect(split.title, 'Sort ticks');
    expect(split.details, 'They sink.');
    expect(split.revertable, isFalse);
    expect(split.canRevert(first: false), isFalse);
    expect(older.title, 'Raise the goal');
    expect(older.details, 'To 12 cards.');
    expect(older.revertable, isNull);
    expect(older.canRevert(first: false), isTrue);
    expect(older.canRevert(first: true), isFalse);
  });

  test('a diff reads file by file, or whole from an older server', () {
    final diff = AppDiff.fromJson({
      'commit': 'aaaa',
      'diff': 'commit aaaa\n',
      'files': [
        {
          'path': 'app.json',
          'status': 'modified',
          'patch': '@@ -1 +1 @@\n-a\n+b\n',
        },
        {'path': 'notes.txt', 'status': 'added', 'patch': ''},
        {'path': 'old.txt', 'status': 'deleted', 'patch': ''},
        {'status': 'added'},
      ],
    });
    expect(
      [for (final f in diff.files!) f.status],
      [FileChange.modified, FileChange.added, FileChange.deleted],
    );
    expect(AppDiff.fromJson({'diff': 'commit aaaa\n'}).files, isNull);
    expect(
      [for (final (kind, _) in patchLines(diff.files!.first.patch)) kind],
      [DiffKind.header, DiffKind.removed, DiffKind.added],
    );
    expect(
      patchLines('+x\n\\ No newline at end of file\n').last.$1,
      DiffKind.header,
    );
  });

  test('a diff tells its header from what it adds and removes', () {
    final lines = diffLines(
      'commit 5f6c11f\n'
      'Author: you\n'
      '\n'
      '-not a removal, the message\n'
      'diff --git a/app.json b/app.json\n'
      '--- a/app.json\n'
      '+++ b/app.json\n'
      '@@ -1 +1 @@\n'
      '-  "title": "Groceries",\n'
      '+  "title": "Food",\n'
      '   "kind": "list"\n',
    );
    expect(
      [for (final (kind, _) in lines) kind],
      [
        DiffKind.header,
        DiffKind.header,
        DiffKind.header,
        DiffKind.header,
        DiffKind.header,
        DiffKind.header,
        DiffKind.header,
        DiffKind.header,
        DiffKind.removed,
        DiffKind.added,
        DiffKind.context,
      ],
    );
  });

  test('a time is said shortly, by its day', () {
    final now = DateTime(2026, 10, 12, 12);
    expect(whenShort(DateTime(2026, 10, 12, 8, 14), now), 'Today 08:14');
    expect(whenShort(DateTime(2026, 10, 11, 20, 30), now), 'Yesterday 20:30');
    expect(whenShort(DateTime(2026, 10, 9, 7, 40), now), '9 Oct 07:40');
    expect(dayText(DateTime(2026, 10, 9, 7, 40), now), '9 Oct');
  });

  test('the state reads its line and data', () {
    final state = AppState.fromJson({
      'line': 7,
      'data': {'items': []},
      'restorable_from': 3,
    });
    expect(state.line, 7);
    expect(state.restorableFrom, 3);
    expect(AppState.fromJson({'line': 7}).restorableFrom, isNull);
    expect(prettyJson(state.data), '{\n  "items": []\n}');
  });

  test('a diff shows from its first file, its header said elsewhere', () {
    expect(
      diffBody('commit 5f6c11f\nAuthor: you\n\ndiff --git a/x b/x\n+y\n'),
      'diff --git a/x b/x\n+y\n',
    );
    expect(diffBody('commit 5f6c11f\n'), 'commit 5f6c11f\n');
  });
}
