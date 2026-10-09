import 'package:anywherellm/core/created.dart';
import 'package:anywherellm/core/outputs.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _file(Map<String, Object?> change) => {
  'id': 'project/report.pdf',
  'name': 'report.pdf',
  'dir': '',
  'size': 2048,
  'modified': 1791908153,
  'area': 'project',
  ...change,
};

void main() {
  group('a created file', () {
    test('is read from what the host lists', () {
      final file = CreatedFile.fromJson(
        _file({
          'id': 'threads/12/scratch/out.txt',
          'name': 'out.txt',
          'dir': 'scratch',
          'area': 'work',
          'expires': 1792512953,
        }),
      )!;
      expect(file.area, CreatedArea.work);
      expect(file.dir, 'scratch');
      expect(file.modified, DateTime.fromMillisecondsSinceEpoch(1791908153000));
      expect(file.expires, DateTime.fromMillisecondsSinceEpoch(1792512953000));
      expect(file.url, isNull);
    });

    test('is nothing when what the app needs is missing or unknown', () {
      expect(CreatedFile.fromJson(null), isNull);
      expect(CreatedFile.fromJson(_file({'area': 'cloud'})), isNull);
      expect(CreatedFile.fromJson(_file({'id': 3})), isNull);
      expect(CreatedFile.fromJson(_file({'size': 'big'})), isNull);
    });

    test('is a page only when it is a web page on the web', () {
      bool page(String name, String area, [String? url]) =>
          CreatedFile.fromJson(
            _file({'name': name, 'area': area, 'url': ?url}),
          )!.isPage;
      expect(
        page('index.html', 'public', 'https://h:8447/q3/index.html'),
        isTrue,
      );
      expect(
        page('INDEX.HTM', 'public', 'https://h:8447/q3/index.htm'),
        isTrue,
      );
      expect(
        page('data.json', 'public', 'https://h:8447/q3/data.json'),
        isFalse,
      );
      expect(page('index.html', 'project'), isFalse);
    });
  });

  group('the list', () {
    test('keeps the files it can read and says how full the room is', () {
      final list = CreatedList.fromJson({
        'workspace': 'q3',
        'used': 4294967296,
        'warn': 4294967296,
        'limit': 5368709120,
        'truncated': true,
        'files': [
          _file({}),
          'junk',
          _file({'area': 'nowhere'}),
        ],
      })!;
      expect(list.files, hasLength(1));
      expect(list.truncated, isTrue);
      expect(list.nearFull, isTrue);
      expect(list.fraction, closeTo(0.8, 0.001));
    });

    test(
      'is nothing when it is not a list, and a room with no limit is empty',
      () {
        expect(CreatedList.fromJson({'files': 'no'}), isNull);
        expect(CreatedList.fromJson([]), isNull);
        const none = CreatedList();
        expect(none.fraction, 0);
        expect(none.nearFull, isFalse);
      },
    );
  });

  group('a mark', () {
    final now = DateTime(2026, 10, 9, 12);
    CreatedFile file(String area, {DateTime? expires}) => CreatedFile(
      id: 'x',
      name: 'x.txt',
      dir: '',
      size: 1,
      modified: now,
      area: CreatedArea.named(area)!,
      expires: expires,
    );

    test('is said only for a file that differs from a kept one', () {
      expect(createdMark(file('project'), now), isNull);
      expect(createdMark(file('public'), now), 'On the web');
      expect(createdMark(file('shared'), now), 'Other workspaces can read');
    });

    test('says how many days a working file has left, rounded up', () {
      String? goes(Duration left) =>
          createdMark(file('work', expires: now.add(left)), now);
      expect(goes(const Duration(days: 3)), 'Goes in 3 days');
      expect(goes(const Duration(days: 2, hours: 1)), 'Goes in 3 days');
      expect(goes(const Duration(hours: 5)), 'Goes in 1 day');
      expect(goes(Duration.zero), 'Goes soon');
      expect(goes(const Duration(days: -1)), 'Goes soon');
      expect(createdMark(file('work'), now), 'Goes after a week');
    });
  });

  test(
    'the route is on the cards port, the workspace and the file encoded',
    () {
      final uri = createdRoute(
        Uri.parse('https://host.example.ts.net:3001'),
        'q 3',
        '/download',
        'project/a b.txt',
      );
      expect(
        uri.toString(),
        'https://host.example.ts.net:8445/_live/sandbox/files/q%203/download'
        '?path=project%2Fa+b.txt',
      );
    },
  );

  test('a size can be gigabytes', () {
    expect(sizeText(5 * 1024 * 1024 * 1024), '5.0 GB');
    expect(sizeText(32379), '31.6 KB');
  });
}
