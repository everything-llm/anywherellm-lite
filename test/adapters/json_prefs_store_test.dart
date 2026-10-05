import 'dart:io';

import 'package:everything/adapters/json_prefs_store.dart';
import 'package:everything/core/ports.dart';
import 'package:everything/core/prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('prefs'));
  tearDown(() async => dir.delete(recursive: true));

  test('with no file, the defaults', () async {
    final prefs = await JsonPrefsStore(File('${dir.path}/none/prefs.json'))
        .load();
    expect(prefs.groundedOnly, isTrue);
  });

  test('saves, making the folder, and loads what it saved', () async {
    final file = File('${dir.path}/nilson/prefs.json');
    await JsonPrefsStore(file).save(const Prefs(groundedOnly: false));
    expect(file.existsSync(), isTrue);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
    expect((await JsonPrefsStore(file).load()).groundedOnly, isFalse);
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
