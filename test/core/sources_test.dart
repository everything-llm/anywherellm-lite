import 'package:everything/core/prefs.dart';
import 'package:everything/core/server_models.dart';
import 'package:everything/core/sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('embedded files come first and on, then the switched-off ones', () {
    final files = mergeSources(
      [const WorkspaceDoc(path: 'f/a.json', title: 'roadmap.pdf', words: 1)],
      [const OffDoc(path: 'f/b.json', title: 'budget.xlsx')],
    );
    expect(files.map((f) => (f.title, f.on)), [
      ('roadmap.pdf', true),
      ('budget.xlsx', false),
    ]);
  });

  test('a file both embedded and remembered as off counts as on', () {
    final files = mergeSources(
      [const WorkspaceDoc(path: 'f/a.json', title: 'a.md')],
      [const OffDoc(path: 'f/a.json', title: 'a.md')],
    );
    expect(files.single.on, isTrue);
  });

  test('a file shows its type and word count', () {
    const file = SourceFile(
      path: 'p',
      title: 'notes.md',
      on: true,
      words: 1204,
    );
    expect(file.tile, 'MD');
    expect(file.meta, '1204 words');
    expect(const SourceFile(path: 'p', title: 'README', on: true).meta, '');
    expect(const SourceFile(path: 'p', title: 'README', on: true).tile, 'FILE');
  });
}
