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
    expect(prefs.lastFolders, isEmpty);
  });

  test('a file that is not JSON, or not UTF-8, gives the defaults', () async {
    final file = File('${dir.path}/prefs.json');
    for (final bytes in [
      '{"theme": "dark"'.codeUnits,
      '[1, 2'.codeUnits,
      [0x7b, 0xff, 0xfe, 0x7d],
    ]) {
      await file.writeAsBytes(bytes);
      final prefs = await JsonPrefsStore(file).load();
      expect(prefs.theme, ThemePref.system);
      expect(prefs.lastFolders, isEmpty);
    }
  });

  test('saves, making the folder, and loads what it saved', () async {
    final file = File('${dir.path}/anywherellm/prefs.json');
    await JsonPrefsStore(file)
        .save(const Prefs(lastFolders: {'https://s': 'Manuals'}));
    expect(file.existsSync(), isTrue);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
    expect(
      (await JsonPrefsStore(file).load()).lastFolders['https://s'],
      'Manuals',
    );
  });

  test('saves at once land in order, the last one winning', () async {
    final store = JsonPrefsStore(File('${dir.path}/anywherellm/prefs.json'));
    await Future.wait([
      store.save(const Prefs(lastFolders: {'https://s': 'Manuals'})),
      store.save(const Prefs()),
    ]);
    expect((await store.load()).lastFolders, isEmpty);
  });

  test('saves made while one writes go as the newest alone', () async {
    final file = File('${dir.path}/anywherellm/prefs.json');
    final store = JsonPrefsStore(file);
    const themes = [ThemePref.light, ThemePref.dark, ThemePref.system];
    // The first starts writing; the other two wait, and only the last is written.
    final saves = [for (final theme in themes) store.save(Prefs(theme: theme))];
    await Future.wait(saves);
    expect((await store.load()).theme, ThemePref.system);
    await store.save(const Prefs(theme: ThemePref.dark));
    expect((await store.load()).theme, ThemePref.dark);
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
