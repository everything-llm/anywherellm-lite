import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/core/sources.dart';
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
      path: 'custom-documents/notes.md.json',
      title: 'notes.md',
      on: true,
      words: 1204,
    );
    expect(file.tile, 'MD');
    expect(file.meta, '1204 words');
    expect(const SourceFile(path: 'p', title: 'README', on: true).meta, '');
  });

  test('the type comes from the stored name, whatever the title', () {
    const id = '6c3f0a1e-2b4d-4c5e-8f90-a1b2c3d4e5f6';
    String tile(String name, String title) =>
        SourceFile(path: 'custom-documents/$name', title: title, on: true).tile;
    expect(tile('report.pdf-$id.json', 'Quarterly report'), 'PDF');
    expect(tile('Q3-roadmap.pdf-${id.toUpperCase()}.json', 'Q3'), 'PDF');
    expect(tile('url-example.com_pricing-$id.json', 'Node.js 22'), 'WEB');
    expect(tile('raw-meeting-notes-$id.json', 'Meeting notes.md'), 'FILE');
    expect(tile('README.json', 'README.md'), 'FILE');
  });
}
