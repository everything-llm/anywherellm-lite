import 'package:flutter_test/flutter_test.dart';
import 'package:everything/core/list_filter.dart';

class _Doc {
  const _Doc(this.title, this.kind, this.words);
  final String title;
  final String kind;
  final String words;
}

const _docs = [
  _Doc('Concision', 'report', 'docs evidence'),
  _Doc('Onboarding', 'report', 'docs people'),
  _Doc('Template', 'template', 'docs'),
  _Doc('Spec', 'spec', 'evidence'),
];

FilterResult<_Doc> _run(ListFilter filter) => filterList(
  _docs,
  filter,
  (d) => Facts(text: '${d.title} ${d.words}', facet: d.kind),
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

  test('words match the text, ignoring case', () {
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

  test('editing one part keeps the other', () {
    const start = ListFilter(query: 'a', facet: 'f');
    expect(start.copyWith(query: 'b').facet, 'f');
    expect(start.copyWith(facet: '').query, 'a');
    expect(start.active, isTrue);
  });

  test('the count line says when a filter hides items', () {
    expect(countLine(4, 4, 'documents'), '4 documents');
    expect(countLine(1, 4, 'documents'), 'Showing 1 of 4 documents');
  });
}
