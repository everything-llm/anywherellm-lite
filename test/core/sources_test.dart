import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/core/sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LibraryFolder folder(String name, List<String> titles) =>
      LibraryFolder(name, [
        for (final title in titles)
          LibraryDoc(path: '$name/$title.json', title: title),
      ]);

  test(
    'the library is listed folder by folder, on where the workspace has it',
    () {
      final files = librarySources(
        [
          folder('custom-documents', ['roadmap.pdf', 'budget.xlsx']),
          folder('Manuals', ['boiler.pdf']),
        ],
        [
          const WorkspaceDoc(
            path: 'Manuals/boiler.pdf.json',
            title: 'boiler.pdf',
            words: 9,
            pinned: true,
          ),
        ],
      );
      expect(files.map((f) => (f.title, f.folder, f.on, f.pinned)), [
        ('roadmap.pdf', 'custom-documents', false, false),
        ('budget.xlsx', 'custom-documents', false, false),
        ('boiler.pdf', 'Manuals', true, true),
      ]);
      expect(files.last.words, 9, reason: 'the workspace\'s count fills a gap');
    },
  );

  test('a document the workspace has that the library did not list is on', () {
    final files = librarySources(
      [
        folder('custom-documents', ['a.md']),
      ],
      [const WorkspaceDoc(path: 'gone/b.json', title: 'b.md')],
    );
    expect(files.map((f) => (f.title, f.on)), [
      ('a.md', false),
      ('b.md', true),
    ]);
    expect(
      librarySources(null, [
        const WorkspaceDoc(path: 'f/a.json', title: 'a'),
      ]).single.on,
      isTrue,
    );
  });

  test('files go by folder in the order each folder first comes', () {
    final groups = byFolder(
      librarySources(
        [
          folder('a', ['1']),
          folder('b', ['2']),
        ],
        [const WorkspaceDoc(path: 'a/3.json', title: '3')],
      ),
    );
    expect(
      groups.map((g) => '${g.$1}: ${g.$2.map((f) => f.title).join(', ')}'),
      ['a: 1, 3', 'b: 2'],
    );
  });

  test('a file shows its type and word count', () {
    const file = SourceFile(
      path: 'custom-documents/notes.md.json',
      title: 'notes.md',
      on: true,
      words: 1204,
    );
    expect(file.tile, 'MD');
    expect(file.meta, '1,204 words');
    expect(const SourceFile(path: 'p', title: 'README', on: true).meta, '');
  });

  test(
    'a switched-off file says it is not used, and a pinned one is read in full',
    () {
      const off = SourceFile(
        path: 'p',
        title: 'Pricing',
        on: false,
        words: 1040,
      );
      expect(off.meta, 'Not used · 1,040 words');
      const uncounted = SourceFile(path: 'p', title: 'Pricing', on: false);
      expect(uncounted.meta, 'Not used');
      const whole = SourceFile(
        path: 'p',
        title: 'Boiler manual.pdf',
        on: true,
        words: 9300,
        pinned: true,
      );
      expect(whole.meta, '9,300 words · Read in full');
    },
  );

  test('where a document came from', () {
    const id = '6c3f0a1e-2b4d-4c5e-8f90-a1b2c3d4e5f6';
    const file = SourceFile(
      path: 'Bills/home-insurance.pdf-$id.json',
      title: 'Home insurance',
      on: true,
      fileName: 'Home insurance.pdf',
    );
    expect(
      (file.origin.label, file.from),
      ('Uploaded file', 'Home insurance.pdf'),
    );
    expect(
      (file.folder, file.storedName),
      ('Bills', 'home-insurance.pdf-$id.json'),
    );
    const page = SourceFile(
      path: 'f/url-example.com-$id.json',
      title: 'Example',
      on: true,
      web: true,
      link: 'https://example.com/',
    );
    expect(
      (page.origin.label, page.from),
      ('Web page', 'https://example.com/'),
    );
    const text = SourceFile(
      path: 'f/raw-notes-$id.json',
      title: 'notes',
      on: true,
    );
    expect((text.origin.label, text.from), ('Pasted text', null));
  });

  test('when a document was added reads as a date', () {
    expect(addedText('10/12/2026, 9:30:00 AM'), '12 Oct 2026');
    expect(addedText('16/1/2024, 15:07:00'), '16 Jan 2024');
    expect(addedText('16.1.2024, 15:07:00'), '16 Jan 2024');
    expect(addedText('2024-01-16'), '16 Jan 2024');
    expect(addedText('yesterday'), 'yesterday');
    expect(addedText('13/13/2024'), '13/13/2024');
  });

  test('a new folder needs a name that is not a path', () {
    expect(folderProblem('Manuals'), isNull);
    expect(folderProblem('  '), isNotNull);
    expect(folderProblem('a/b'), isNotNull);
    expect(folderProblem(r'a\b'), isNotNull);
    expect(folderProblem('..'), isNotNull);
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

  test('the type follows the server on whether a file is a web page', () {
    const id = '6c3f0a1e-2b4d-4c5e-8f90-a1b2c3d4e5f6';
    String tile(String name, bool? web) => SourceFile(
      path: 'custom-documents/$name',
      title: name,
      on: true,
      web: web,
    ).tile;
    expect(tile('url-list.md-$id.json', false), 'MD');
    expect(tile('url-list.md-$id.json', null), 'WEB');
    expect(tile('example.com-guide.html-$id.json', true), 'WEB');
  });

  test('whether a file is a web page comes from the library', () {
    final [file] = librarySources([
      LibraryFolder('f', const [
        LibraryDoc(path: 'f/a.json', title: 'a', web: true),
      ]),
    ], const []);
    expect((file.web, file.tile), (true, 'WEB'));
  });
}
