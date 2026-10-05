import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/list_filter.dart';
import '../widgets/basics.dart';
import '../widgets/fields.dart';
import '../widgets/rows.dart';
import '../widgets/select.dart';
import 'page_frame.dart';

/// Builds one row of the list, with the corners it shares with the list's rounded edge.
typedef LibraryRowBuilder<T> = Widget Function(
  BuildContext context,
  T item,
  BorderRadius corners,
);

/// A list page: the title, then the items grouped, narrowed by a search and one facet.
///
/// The narrowing lives here and goes when the page does.
class LibraryList<T> extends StatefulWidget {
  const LibraryList({
    super.key,
    required this.title,
    required this.sub,
    required this.noun,
    required this.load,
    required this.facts,
    required this.group,
    required this.row,
    required this.searchHint,
    required this.facetLabel,
    required this.allFacets,
    required this.emptyTitle,
    required this.emptyText,
  });

  final String title;
  final String sub;

  /// What the items are called in the count line: `documents`, `skills`.
  final String noun;
  final Future<List<T>> Function() load;
  final Facts Function(T) facts;
  final String Function(T) group;
  final LibraryRowBuilder<T> row;
  final String searchHint;
  final String facetLabel;
  final String allFacets;

  /// Shown when the list holds nothing at all.
  final String emptyTitle;
  final String emptyText;

  @override
  State<LibraryList<T>> createState() => _LibraryListState<T>();
}

class _LibraryListState<T> extends State<LibraryList<T>> {
  final _search = TextEditingController();
  ListFilter _filter = const ListFilter();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clear() {
    _search.clear();
    setState(() => _filter = const ListFilter());
  }

  @override
  Widget build(BuildContext context) {
    return LoadPage<List<T>>.slivers(
      load: widget.load,
      slivers: (context, items) {
        final head = SliverToBoxAdapter(
          child: PageHead(widget.title, sub: widget.sub),
        );
        if (items.isEmpty) {
          return [
            head,
            SliverToBoxAdapter(
              child: EmptyState(widget.emptyTitle, widget.emptyText),
            ),
          ];
        }
        final result = filterList(
          items,
          _filter,
          widget.facts,
          allFacets: widget.allFacets,
        );
        return [
          head,
          SliverToBoxAdapter(child: _controls(result, items.length)),
          if (result.shown.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                'Nothing matches',
                'Try fewer words, or clear the filters.',
              ),
            ),
          for (final MapEntry(key: group, value: rows) in groupBy(
            result.shown,
            widget.group,
          ).entries)
            SliverListSection(
              group,
              count: rows.length,
              itemBuilder: (context, i, corners) =>
                  widget.row(context, rows[i], corners),
            ),
        ];
      },
    );
  }

  Widget _controls(FilterResult<T> result, int total) {
    final search = SearchField(
      controller: _search,
      hint: widget.searchHint,
      onChanged: (value) =>
          setState(() => _filter = _filter.copyWith(query: value)),
    );
    final select = NilsSelect(
      label: widget.facetLabel,
      value: _filter.facet,
      options: [
        for (final f in result.facets) (value: f.value, label: f.label),
      ],
      onChanged: (value) =>
          setState(() => _filter = _filter.copyWith(facet: value)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 520
              ? Row(
                  spacing: 8,
                  children: [
                    Expanded(child: search),
                    SizedBox(width: 210, child: select),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [search, select],
                ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Semantics(
                liveRegion: true,
                child: HelpText(
                  countLine(result.shown.length, total, widget.noun),
                ),
              ),
            ),
            if (_filter.active) NilsLink('Clear filters', onTap: _clear),
          ],
        ),
      ],
    );
  }
}
