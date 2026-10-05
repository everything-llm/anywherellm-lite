// Searching and filtering a list: words and one facet, such as a folder.
//
// Pure functions over whatever the list holds; [Facts] says what each item is searched by.

/// What one list item is searched and filtered by.
class Facts {
  const Facts({required this.text, required this.facet});

  /// The words a search looks in.
  final String text;

  /// The one value the select filters on.
  final String facet;
}

/// What the person has asked the list to narrow to.
class ListFilter {
  const ListFilter({this.query = '', this.facet = ''});

  final String query;

  /// Empty for all.
  final String facet;

  bool get active => query.trim().isNotEmpty || facet.isNotEmpty;

  ListFilter copyWith({String? query, String? facet}) =>
      ListFilter(query: query ?? this.query, facet: facet ?? this.facet);
}

class FacetOption {
  const FacetOption(this.value, this.label);

  /// Empty for the option that shows everything.
  final String value;
  final String label;
}

class FilterResult<T> {
  const FilterResult({required this.shown, required this.facets});

  final List<T> shown;

  /// "All", then each facet with how many items the search leaves in it.
  final List<FacetOption> facets;
}

/// [items] narrowed by [filter]. Words match the text, ignoring case; the facet matches exactly.
FilterResult<T> filterList<T>(
  List<T> items,
  ListFilter filter,
  Facts Function(T) facts, {
  required String allFacets,
}) {
  final query = filter.query.trim().toLowerCase();
  final searched = [
    for (final item in items)
      if (facts(item) case final f
          when query.isEmpty || f.text.toLowerCase().contains(query))
        (item, f),
  ];
  final facetCounts = <String, int>{};
  for (final (_, f) in searched) {
    facetCounts[f.facet] = (facetCounts[f.facet] ?? 0) + 1;
  }
  return FilterResult(
    shown: [
      for (final (item, f) in searched)
        if (filter.facet.isEmpty || f.facet == filter.facet) item,
    ],
    facets: [
      FacetOption('', allFacets),
      for (final name in {
        ...facetCounts.keys,
        if (filter.facet.isNotEmpty) filter.facet,
      }.toList()..sort())
        FacetOption(name, '$name (${facetCounts[name] ?? 0})'),
    ],
  );
}

/// `12 documents`, or `Showing 3 of 12 documents` when a filter hides some.
String countLine(int shown, int total, String noun) =>
    shown == total ? '$total $noun' : 'Showing $shown of $total $noun';
