// Searching and filtering a library list: words, one facet (type or topic), and tags.
//
// Pure functions over whatever the list holds; [Facts] says what each item is searched by.

/// What one list item is searched and filtered by.
class Facts {
  const Facts({required this.text, required this.facet, this.tags = const []});

  /// The words a search looks in: title and summary.
  final String text;

  /// The one value the select filters on: a research type or a skill topic.
  final String facet;
  final List<String> tags;
}

/// What the person has asked the list to narrow to.
class ListFilter {
  const ListFilter({this.query = '', this.facet = '', this.tags = const {}});

  final String query;

  /// Empty for all.
  final String facet;
  final Set<String> tags;

  bool get active =>
      query.trim().isNotEmpty || facet.isNotEmpty || tags.isNotEmpty;

  ListFilter copyWith({String? query, String? facet, Set<String>? tags}) =>
      ListFilter(
        query: query ?? this.query,
        facet: facet ?? this.facet,
        tags: tags ?? this.tags,
      );

  ListFilter toggled(String tag) => copyWith(
    tags: tags.contains(tag) ? ({...tags}..remove(tag)) : {...tags, tag},
  );
}

class TagChoice {
  const TagChoice({
    required this.label,
    required this.count,
    required this.pressed,
  });

  final String label;

  /// How many of the items the search and the facet leave have this tag.
  final int count;
  final bool pressed;

  /// A tag that would show nothing more, unless it is already pressed.
  bool get dim => !pressed && count == 0;
}

class FacetOption {
  const FacetOption(this.value, this.label);

  /// Empty for the option that shows everything.
  final String value;
  final String label;
}

/// How many tag chips show before the "All tags" panel.
const topTags = 8;

/// The most tags the panel lists at once.
const panelLimit = 60;

class FilterResult<T> {
  const FilterResult({
    required this.shown,
    required this.tags,
    required this.facets,
  });

  final List<T> shown;

  /// Every tag in the list, most used first, counted over what the search and facet leave.
  final List<TagChoice> tags;

  /// "All", then each facet with how many items the search leaves in it.
  final List<FacetOption> facets;

  /// The chips shown before the panel: the most used tags, then any pressed one below them.
  List<TagChoice> get mainTags => [
    ...tags.take(topTags),
    ...tags.skip(topTags).where((tag) => tag.pressed),
  ];

  bool get hasMoreTags => tags.length > topTags;
}

/// [items] narrowed by [filter]. Words match the text and the tags, ignoring case; the facet
/// matches exactly; every pressed tag must be present.
FilterResult<T> filterList<T>(
  List<T> items,
  ListFilter filter,
  Facts Function(T) facts, {
  required String allFacets,
}) {
  final query = filter.query.trim().toLowerCase();
  final all = [for (final item in items) (item, facts(item))];
  final searched = [
    for (final entry in all)
      if (query.isEmpty ||
          '${entry.$2.text} ${entry.$2.tags.join(' ')}'.toLowerCase().contains(
            query,
          ))
        entry,
  ];
  final faceted = [
    for (final entry in searched)
      if (filter.facet.isEmpty || entry.$2.facet == filter.facet) entry,
  ];
  final shown = [
    for (final entry in faceted)
      if (filter.tags.every(entry.$2.tags.contains)) entry.$1,
  ];
  final total = _counts(all.expand((entry) => entry.$2.tags));
  final current = _counts(faceted.expand((entry) => entry.$2.tags));
  final tags = [
    for (final label
        in total.keys.toList()..sort((a, b) {
          final byUse = total[b]!.compareTo(total[a]!);
          return byUse != 0 ? byUse : a.compareTo(b);
        }))
      TagChoice(
        label: label,
        count: current[label] ?? 0,
        pressed: filter.tags.contains(label),
      ),
  ];
  final facetCounts = _counts(searched.map((entry) => entry.$2.facet));
  return FilterResult(
    shown: shown,
    tags: tags,
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

Map<String, int> _counts(Iterable<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  return counts;
}

/// The tags whose name holds [query], ignoring case.
List<TagChoice> matchingTags(List<TagChoice> tags, String query) {
  final needle = query.trim().toLowerCase();
  return [
    for (final tag in tags)
      if (needle.isEmpty || tag.label.toLowerCase().contains(needle)) tag,
  ];
}

/// The first [panelLimit] of [matching], which is what the panel lists.
List<TagChoice> panelTags(List<TagChoice> matching) =>
    matching.take(panelLimit).toList();

/// What sits under the panel's list: that it was cut, or that nothing matched.
String panelNote(List<TagChoice> matching, String query) {
  if (matching.length > panelLimit) {
    return 'Showing $panelLimit of ${matching.length}. Type to narrow the list.';
  }
  return matching.isEmpty ? 'No tag matches "${query.trim()}".' : '';
}

/// `12 documents`, or `Showing 3 of 12 documents` when a filter hides some.
String countLine(int shown, int total, String noun) =>
    shown == total ? '$total $noun' : 'Showing $shown of $total $noun';
