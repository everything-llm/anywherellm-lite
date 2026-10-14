import 'package:anywherellm/core/activity.dart';
import 'package:anywherellm/core/library.dart';
import 'package:anywherellm/core/schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the Library', () {
    test('apps and files are read, each kept when it is whole', () {
      final library = libraryOf({
        'apps': [
          {
            'title': 'Groceries',
            'page': '/apps-lean/g1.html',
            'workspace': 'Household',
            'workspaceSlug': 'household',
            'changed': '2026-10-13T18:40:00Z',
            'change': 'Added Eggs',
          },
          {'title': 'No page'},
          {'title': 'Elsewhere', 'page': 'https://evil.example/x.html'},
          {'page': '/apps-lean/x.html'},
        ],
        'files': [
          {
            'storageFilename': 'pdf-1.pdf',
            'name': 'Quote.pdf',
            'type': 'PdfFileDownload',
            'size': 2048,
            'workspaceSlug': 'household',
            'createdAt': '2026-10-13T21:05:00Z',
            'thread': 't1',
          },
          {'storageFilename': '../secret', 'name': 'Bad'},
          {'name': 'No storage name'},
        ],
      });
      expect(library.apps.map((a) => a.title), ['Groceries']);
      final app = library.apps.single;
      expect(app.change, 'Added Eggs');
      expect(app.changed, DateTime.utc(2026, 10, 13, 18, 40));
      expect(app.isIn('household'), isTrue);
      expect(app.isIn('q3'), isFalse);
      expect(library.files.map((f) => f.file.name), ['Quote.pdf']);
      final file = library.files.single;
      expect(file.file.storageName, 'pdf-1.pdf');
      expect(file.file.size, 2048);
      expect(file.file.isImage, isFalse);
      expect(file.isIn('household'), isTrue);
    });

    test('a file without a type is a picture by its name', () {
      final library = libraryOf({
        'files': [
          {'storageFilename': 'img-1.PNG', 'name': 'cat.PNG'},
          {'storageFilename': 'data.csv', 'name': 'data.csv'},
        ],
      });
      expect(library.files.map((f) => f.file.isImage), [true, false]);
    });

    test('a Library the toolkit left out is empty', () {
      expect(libraryOf(null).apps, isEmpty);
      expect(libraryOf({'apps': 'nonsense'}).files, isEmpty);
    });
  });

  group('the Activity', () {
    test('an event is read with its kind, outcome and link', () {
      final page = activityOf({
        'events': [
          {
            'id': 9,
            'at': '2026-10-14T16:00:00Z',
            'kind': 'task',
            'title': 'Morning brief',
            'workspace': 'Household',
            'outcome': 'failed',
            'detail': 'The site answered 503.',
            'link': {'slug': 'household', 'thread': 't1'},
          },
          {
            'at': '2026-10-14T10:00:00Z',
            'kind': 'app',
            'title': 'Groceries',
            'outcome': 'ok',
            'link': '/apps-lean/g1.html',
          },
          {
            'at': '2026-10-14T09:00:00Z',
            'kind': 'something new',
            'title': 'Odd',
            'outcome': 'maybe',
            'link': 'not a path',
          },
          {'title': 'No time'},
          {'at': '2026-10-14T08:00:00Z'},
        ],
        'more': true,
      });
      expect(page.more, isTrue);
      expect(page.events.map((e) => e.title), [
        'Morning brief',
        'Groceries',
        'Odd',
      ]);
      final [failed, app, odd] = page.events;
      expect(failed.id, '9');
      expect(failed.kind, ActivityKind.task);
      expect(failed.outcome, ActivityOutcome.failed);
      expect(failed.detail, 'The site answered 503.');
      expect(failed.link, isA<ChatLink>());
      expect((failed.link! as ChatLink).thread, 't1');
      expect(app.outcome, ActivityOutcome.ok);
      expect((app.link! as PageLink).path, '/apps-lean/g1.html');
      // An outcome it does not know is no verdict, not a success.
      expect(odd.kind, ActivityKind.other);
      expect(odd.outcome, ActivityOutcome.unknown);
      expect(odd.link, isNull);
      expect(odd.key, isNot(failed.key));
    });

    test('a list with no more says so', () {
      expect(activityOf({'events': []}).more, isFalse);
      expect(activityOf(null).events, isEmpty);
    });
  });

  test('a day is Today, Yesterday or a date', () {
    final now = DateTime(2026, 10, 14, 12);
    expect(dayText(DateTime(2026, 10, 14, 6), now), 'Today');
    expect(dayText(DateTime(2026, 10, 13, 21), now), 'Yesterday');
    expect(dayText(DateTime(2026, 10, 6, 9), now), 'Tue 6 Oct');
  });
}
