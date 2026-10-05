import 'package:flutter_test/flutter_test.dart';
import 'package:everything/core/list_filter.dart';

class _Doc {
  const _Doc(this.title, this.kind, this.tags);
  final String title;
  final String kind;
  final List<String> tags;
}

const _docs = [
  _Doc('Concision', 'report', ['docs', 'evidence']),
  _Doc('Onboarding', 'report', ['docs', 'people']),
  _Doc('Template', 'template', ['docs']),
  _Doc('Spec', 'spec', ['evidence']),
];

FilterResult<_Doc> _run(ListFilter filter) => filterList(
  _docs,
  filter,
  (d) => Facts(text: d.title, facet: d.kind, tags: d.tags),
  allFacets: 'All types',
);

List<String> _titles(FilterResult<_Doc> r) => [
  for (final d in r.shown) d.title,
];

void main() {
  test('no filter shows everything', () {
    final result = _run(const ListFilter());
    expect(_titles(result), ['Concision', 'Onboarding', 'Template', 'Spec']);
    expect(const ListFilter().active, isFalse);
  });

  test('words match the text and the tags, ignoring case', () {
    expect(_titles(_run(const ListFilter(query: 'ONBOARD'))), ['Onboarding']);
    expect(_titles(_run(const ListFilter(query: 'evidence'))), [
      'Concision',
      'Spec',
    ]);
    expect(_titles(_run(const ListFilter(query: '  '))), hasLength(4));
  });

  test('the facet matches exactly', () {
    expect(_titles(_run(const ListFilter(facet: 'report'))), [
      'Concision',
      'Onboarding',
    ]);
  });

  test('every pressed tag must be present', () {
    expect(_titles(_run(const ListFilter(tags: {'docs', 'evidence'}))), [
      'Concision',
    ]);
  });

  test('tags are most used first, then by name, counted over the facet', () {
    final result = _run(const ListFilter(facet: 'report'));
    expect(
      [for (final t in result.tags) (t.label, t.count)],
      [('docs', 2), ('evidence', 1), ('people', 1)],
    );
    final all = _run(const ListFilter()).tags;
    expect([for (final t in all) t.label], ['docs', 'evidence', 'people']);
  });

  test('a tag with nothing left is dim unless pressed', () {
    final result = _run(const ListFilter(facet: 'spec', tags: {'people'}));
    final people = result.tags.firstWhere((t) => t.label == 'people');
    final docs = result.tags.firstWhere((t) => t.label == 'docs');
    expect(people.pressed, isTrue);
    expect(people.dim, isFalse);
    expect(docs.dim, isTrue);
  });

  test('facet options count what the search leaves', () {
    final result = _run(const ListFilter(query: 'docs'));
    expect(
      [for (final f in result.facets) (f.value, f.label)],
      [
        ('', 'All types'),
        ('report', 'report (2)'),
        ('template', 'template (1)'),
      ],
    );
  });

  test('the chosen facet stays an option even when the search leaves none', () {
    final result = _run(const ListFilter(query: 'spec', facet: 'template'));
    expect(
      [for (final f in result.facets) f.label],
      ['All types', 'spec (1)', 'template (0)'],
    );
  });

  test('the chips are the top tags plus any pressed one below them', () {
    final many = [
      for (var i = 0; i < 12; i++)
        _Doc('Doc $i', 'report', [
          for (var j = 0; j <= i; j++) 'tag${j.toString().padLeft(2, '0')}',
        ]),
    ];
    FilterResult<_Doc> run(ListFilter f) => filterList(
      many,
      f,
      (d) => Facts(text: d.title, facet: d.kind, tags: d.tags),
      allFacets: 'All',
    );
    final plain = run(const ListFilter());
    expect(plain.mainTags, hasLength(topTags));
    expect(plain.hasMoreTags, isTrue);
    final pressed = run(const ListFilter(tags: {'tag11'}));
    expect(pressed.mainTags, hasLength(topTags + 1));
    expect(pressed.mainTags.last.label, 'tag11');
  });

  test('a small list has no All tags panel', () {
    expect(_run(const ListFilter()).hasMoreTags, isFalse);
  });

  test('toggling a tag and the other edits keep the rest', () {
    const start = ListFilter(query: 'a', facet: 'f', tags: {'x'});
    expect(start.toggled('y').tags, {'x', 'y'});
    expect(start.toggled('x').tags, isEmpty);
    expect(start.copyWith(query: 'b').facet, 'f');
    expect(start.copyWith(facet: '').tags, {'x'});
    expect(start.active, isTrue);
  });

  test('the panel filters by name and says when it cut or found nothing', () {
    final tags = [
      for (var i = 0; i < 70; i++)
        TagChoice(label: 'tag$i', count: 1, pressed: false),
    ];
    List<TagChoice> match(String query) => matchingTags(tags, query);
    expect(panelTags(match('')), hasLength(panelLimit));
    expect(
      panelNote(match(''), ''),
      'Showing 60 of 70. Type to narrow the list.',
    );
    expect(match('TAG6'), hasLength(11));
    expect(panelNote(match('tag6'), 'tag6'), '');
    expect(panelNote(match('zzz'), 'zzz'), 'No tag matches "zzz".');
  });

  test('the count line says when a filter hides items', () {
    expect(countLine(4, 4, 'documents'), '4 documents');
    expect(countLine(1, 4, 'documents'), 'Showing 1 of 4 documents');
  });
}
