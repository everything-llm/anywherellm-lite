import 'package:flutter/material.dart';

import 'layout.dart';
import 'settings/rows.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/buttons.dart';

/// A wide window's [list] beside the [detail] it opens: the list at [Wide.listWidth] of the
/// room, then the detail in what is left, [Wide.gap] apart.
class ListDetail extends StatelessWidget {
  const ListDetail({super.key, required this.list, required this.detail});

  final Widget list;
  final Widget detail;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: Wide.listWidth(box.maxWidth), child: list),
        const SizedBox(width: Wide.gap),
        Expanded(child: detail),
      ],
    ),
  );
}

/// A wide page's [title] over the line [about], the page's own heading.
class PaneTitle extends StatelessWidget {
  const PaneTitle(this.title, {super.key, this.about});

  final String title;
  final String? about;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Semantics(header: true, child: Text(title, style: Type.title(t.ink))),
        if (about case final about?) Text(about, style: Type.note(t.ink)),
      ],
    );
  }
}

/// The bar over a wide page: a way back, heard as [back], where no sidebar shows the way out,
/// then [child], or the page's [title] and [about] with [action] at the line's end, wrapping
/// under it where the line is short.
class PaneHeader extends StatelessWidget {
  const PaneHeader({
    super.key,
    this.title = '',
    this.about,
    this.action,
    this.child,
    required this.back,
    required this.onBack,
  });

  final String title;
  final String? about;
  final Widget? action;

  /// What the bar holds in place of the title and [action], as the Documents page's adders do.
  final Widget? child;
  final String back;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final backShown = !Wide.sidebarShown(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Sizes.header),
      child: Padding(
        padding: EdgeInsets.fromLTRB(backShown ? 16 : 24, 12, 24, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            if (backShown)
              IconBtn.header('back', tooltip: back, onPressed: onBack),
            Expanded(
              child:
                  child ??
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      PaneTitle(title, about: about),
                      ?action,
                    ],
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a list opens, in a card beside it: its [title], on at most [titleLines], with [about]
/// under it, a way back heard as [back] when [onBack] is given, and [actions] at the line's end,
/// over [child], which fills the rest.
class DetailCard extends StatelessWidget {
  const DetailCard({
    super.key,
    required this.title,
    required this.child,
    this.about,
    this.titleLines = 1,
    this.actions = const [],
    this.back = 'Back',
    this.onBack,
  });

  final String title;
  final Widget? about;
  final int titleLines;
  final List<Widget> actions;
  final String back;
  final VoidCallback? onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: cardDecoration(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(onBack == null ? 24 : 12, 16, 16, 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                spacing: 12,
                children: [
                  if (onBack case final onBack?)
                    IconBtn.header('back', tooltip: back, onPressed: onBack),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      spacing: 2,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            maxLines: titleLines,
                            overflow: TextOverflow.ellipsis,
                            style: Type.title(t.ink),
                          ),
                        ),
                        ?about,
                      ],
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A wide window's list: its [rows], each a `ListRow`, in a card.
class ListCard extends StatelessWidget {
  const ListCard(this.rows, {super.key});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: cardDecoration(Tokens.of(context)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: rows,
    ),
  );
}
