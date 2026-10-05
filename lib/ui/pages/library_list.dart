import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/list_filter.dart';
import '../app_scope.dart';
import '../tokens.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/chip.dart';
import '../widgets/fields.dart';
import '../widgets/findings.dart';
import '../widgets/rows.dart';
import '../widgets/select.dart';
import 'page_frame.dart';

/// Builds one row of the list, with the corners it shares with the list's rounded edge.
typedef LibraryRowBuilder<T> = Widget Function(
  BuildContext context,
  T item,
  BorderRadius corners,
  ListFilter filter,
);

/// A library's page: the title, what the last check found in this library, then the items
/// grouped, narrowed by a search, one facet (type or topic) and tags.
///
/// The narrowing lives here and goes when the page does. [library] names the findings to show,
/// `research` or `skills`.
class LibraryList<T> extends StatefulWidget {
  const LibraryList({
    super.key,
    required this.library,
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

  final String library;
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

  /// Shown when the library holds nothing at all.
  final String emptyTitle;
  final String emptyText;

  @override
  State<LibraryList<T>> createState() => _LibraryListState<T>();
}

class _LibraryListState<T> extends State<LibraryList<T>> {
  final _search = TextEditingController();
  final _tagSearch = TextEditingController();
  ListFilter _filter = const ListFilter();
  bool _tagsOpen = false;

  @override
  void dispose() {
    _search.dispose();
    _tagSearch.dispose();
    super.dispose();
  }

  void _clear() {
    _search.clear();
    setState(() => _filter = const ListFilter());
  }

  void _toggleTags() {
    _tagSearch.clear();
    setState(() => _tagsOpen = !_tagsOpen);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return LoadPage<List<T>>.slivers(
      load: () {
        // The sidebar's badges and this page's findings are as old as the last check.
        unawaited(scope.overview.refresh());
        return widget.load();
      },
      slivers: (context, items) {
        final head = SliverToBoxAdapter(child: _Head(widget));
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
                  widget.row(context, rows[i], corners, _filter),
            ),
        ];
      },
    );
  }

  Widget _controls(FilterResult<T> result, int total) {
    final t = Tokens.of(context);
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
        if (result.tags.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final tag in result.mainTags) _chip(tag),
              if (result.hasMoreTags)
                Disclosure(
                  open: _tagsOpen,
                  onToggle: _toggleTags,
                  label: _tagsOpen ? 'Hide all tags' : 'All tags',
                  minHeight: 32,
                  child: Text(
                    _tagsOpen
                        ? 'Hide all tags'
                        : 'All tags (${result.tags.length})',
                    style: TextStyle(color: t.accent, fontSize: 13),
                  ),
                ),
            ],
          ),
        if (_tagsOpen && result.hasMoreTags) _panel(result.tags),
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

  Widget _chip(TagChoice tag) => NilsChip(
    tag.label,
    count: tag.count,
    pressed: tag.pressed,
    dim: tag.dim,
    onTap: () => setState(() => _filter = _filter.toggled(tag.label)),
  );

  Widget _panel(List<TagChoice> tags) {
    final query = _tagSearch.text;
    final matching = matchingTags(tags, query);
    final note = panelNote(matching, query);
    return NilsCard(
      gap: 10,
      padding: const EdgeInsets.all(12),
      children: [
        NilsField(
          controller: _tagSearch,
          label: 'Find a tag',
          hint: 'Find a tag',
          onChanged: (_) => setState(() {}),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final tag in panelTags(matching)) _chip(tag)],
            ),
          ),
        ),
        if (note.isNotEmpty) HelpText(note, status: true),
      ],
    );
  }
}

/// The title and, above the list, what the last check found in this library.
class _Head extends StatelessWidget {
  const _Head(this.list);

  final LibraryList<dynamic> list;

  @override
  Widget build(BuildContext context) {
    final overview = AppScope.of(context).overview;
    return ListenableBuilder(
      listenable: overview,
      builder: (context, _) {
        final findings = overview.findingsFor(list.library);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 22,
          children: [
            PageHead(list.title, sub: list.sub),
            if (findings.isNotEmpty) FindingsSection(findings),
          ],
        );
      },
    );
  }
}

/// A row's tag as a badge, in the accent when the list is filtered by it.
Widget tagBadge(String tag, ListFilter filter) => NilsBadge(
  BadgeSpec(
    tag,
    filter.tags.contains(tag) ? BadgeKind.accent : BadgeKind.plain,
  ),
);
