import 'dart:io';

import 'package:anywherellm/adapters/json_prefs_store.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('prefs'));
  tearDown(() async => dir.delete(recursive: true));

  test('with no file, the defaults', () async {
    final prefs = await JsonPrefsStore(File('${dir.path}/none/prefs.json'))
        .load();
    expect(prefs.switchedOff, isEmpty);
  });

  test('saves, making the folder, and loads what it saved', () async {
    final file = File('${dir.path}/anywherellm/prefs.json');
    await JsonPrefsStore(file).save(
      const Prefs(
        switchedOff: {
          'w': [OffDoc(path: 'f/a.json', title: 'a')],
        },
      ),
    );
    expect(file.existsSync(), isTrue);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
    expect((await JsonPrefsStore(file).load()).offIn('w').single.title, 'a');
  });

  test('saves at once land in order, the last one winning', () async {
    final store = JsonPrefsStore(File('${dir.path}/anywherellm/prefs.json'));
    await Future.wait([
      store.save(
        const Prefs(
          switchedOff: {
            'w': [OffDoc(path: 'f/a.json', title: 'a')],
          },
        ),
      ),
      store.save(const Prefs()),
    ]);
    expect((await store.load()).switchedOff, isEmpty);
  });

  test('a file it cannot write is an ApiException naming the path', () async {
    final blocker = File('${dir.path}/blocker')..writeAsStringSync('');
    final store = JsonPrefsStore(File('${blocker.path}/prefs.json'));
    await expectLater(
      store.save(const Prefs()),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains(blocker.path),
        ),
      ),
    );
  });
}
