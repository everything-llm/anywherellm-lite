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
    expect(file.meta, '1,204 words');
    expect(const SourceFile(path: 'p', title: 'README', on: true).meta, '');
  });

  test('a switched-off file says it is not used', () {
    const off = SourceFile(path: 'p', title: 'Pricing', on: false, words: 1040);
    expect(off.meta, 'Not used · 1,040 words');
    const uncounted = SourceFile(path: 'p', title: 'Pricing', on: false);
    expect(uncounted.meta, 'Not used');
  });

  test('a title loses the extension of the file it came from', () {
    expect(shortTitle('Q3 roadmap.pdf'), 'Q3 roadmap');
    expect(shortTitle('Pricing page'), 'Pricing page');
    expect(shortTitle('notes.v2-final'), 'notes.v2-final');
    expect(shortTitle('Version 2.0'), 'Version 2.0');
    expect(shortTitle('.md'), '.md');
  });

  test('an empty chat suggests from the documents\' names', () {
    List<String> labels(List<String> titles) => [
      for (final s in suggestionsFor(titles)) s.label,
    ];
    expect(labels([]), ['What can I do here?']);
    expect(labels(['Q3 roadmap.pdf']), ['Summarise Q3 roadmap']);
    expect(labels(['Q3 roadmap.pdf', 'Customer interviews.docx', 'x.md']), [
      'Summarise Q3 roadmap',
      'Compare Q3 roadmap with Customer interviews',
    ]);
    expect(
      suggestionsFor(['Q3 roadmap.pdf']).single.prompt,
      'Summarise Q3 roadmap',
    );
  });

  test('a long name is cut in the label and whole in the prompt', () {
    const long =
        'Evidence-Based Gamification Design: What Works, When, and Why.pdf';
    const longer =
        'Open Software Engineering Jobs and Market Outlook in Sweden for a .NET Candidate';
    final [summary, compare] = suggestionsFor([long, longer]);
    // A subtitle after a colon goes first.
    expect(summary.label, 'Summarise Evidence-Based Gamification Design');
    expect(
      summary.prompt,
      'Summarise Evidence-Based Gamification Design: What Works, When, and Why',
    );
    expect(compare.label, 'Compare the first two documents');
    expect(compare.prompt, endsWith('for a .NET Candidate'));
    final [cut] = suggestionsFor([longer]);
    expect(cut.label, 'Summarise Open Software Engineering Jobs and\u2026');
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

  test('a pinned document stays pinned among the merged ones', () {
    final files = mergeSources(
      [const WorkspaceDoc(path: 'a', title: 'A', pinned: true)],
      const [OffDoc(path: 'b', title: 'B')],
    );
    expect([for (final f in files) f.pinned], [true, false]);
  });
}
