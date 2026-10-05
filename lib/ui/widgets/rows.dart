import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';

/// One row of a [NilsList]: a title, a line of detail and, when it can be opened, a chevron.
class NilsRow extends StatelessWidget {
  const NilsRow({
    super.key,
    required this.title,
    this.meta,
    this.mono = false,
    this.monoMeta = false,
    this.leading,
    this.onTap,
    this.radius = BorderRadius.zero,
  });

  final String title;
  final String? meta;
  final bool mono;

  /// The detail line in the mono face too, for a path.
  final bool monoMeta;

  /// An icon before the text, such as a folder's.
  final Widget? leading;
  final VoidCallback? onTap;

  /// The corners of the list this row ends, which the hover fill must follow. A list that clips
  /// its rows, as [NilsList] does, needs none.
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style:
              (mono
                      ? Type.mono(15, weight: FontWeight.w500)
                      : Type.sans(15, weight: FontWeight.w500))
                  .copyWith(color: t.ink),
        ),
        if (meta != null && meta!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            meta!,
            maxLines: onTap != null ? 2 : null,
            overflow: onTap != null ? TextOverflow.ellipsis : null,
            style: monoMeta
                ? Type.mono(12.5, color: t.muted, height: 1.45)
                : Type.sans(13, color: t.muted, height: 1.45),
          ),
        ],
      ],
    );
    final chevron = onTap == null
        ? null
        : NilsIcon('chevron', size: IconSize.sm, color: t.fade);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Row(
          spacing: 12,
          children: [
            ?leading,
            Expanded(child: body),
            ?chevron,
          ],
        ),
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      link: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        hoverColor: t.bg,
        child: content,
      ),
    );
  }
}

/// Rows in a bordered, rounded panel with a rule between them.
class NilsList extends StatelessWidget {
  const NilsList(this.rows, {super.key});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.panel,
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(Sizes.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: t.line2),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// Builds row [index] of a [SliverListSection]. [corners] are the row's share of the list's
/// rounded corners: the top pair on the first row, the bottom pair on the last.
typedef SectionRowBuilder = Widget Function(
  BuildContext context,
  int index,
  BorderRadius corners,
);

/// A [ListSection] as slivers, so only the rows on screen are built. A sliver has no clip, so
/// each row is given its own corners.
class SliverListSection extends StatelessWidget {
  const SliverListSection(
    this.title, {
    super.key,
    required this.count,
    required this.itemBuilder,
  });

  final String title;
  final int count;
  final SectionRowBuilder itemBuilder;

  /// The panel's border is one pixel, so the rows' corners are one pixel tighter.
  static const _inner = Radius.circular(Sizes.card - 1);

  BorderRadius _corners(int index) => BorderRadius.vertical(
    top: index == 0 ? _inner : Radius.zero,
    bottom: index == count - 1 ? _inner : Radius.zero,
  );

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              header: true,
              child: Text(title, style: Type.serif(22, color: t.ink2)),
            ),
          ),
        ),
        DecoratedSliver(
          decoration: BoxDecoration(
            color: t.panel,
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(Sizes.card),
          ),
          sliver: SliverPadding(
            padding: const EdgeInsets.all(1),
            sliver: SliverList.separated(
              itemCount: count,
              itemBuilder: (context, index) =>
                  itemBuilder(context, index, _corners(index)),
              separatorBuilder: (context, _) =>
                  Divider(height: 1, thickness: 1, color: t.line2),
            ),
          ),
        ),
      ],
    );
  }
}

/// A serif heading over a [NilsList].
class ListSection extends StatelessWidget {
  const ListSection(this.title, this.rows, {super.key});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Type.serif(22, color: t.ink2)),
        ),
        const SizedBox(height: 10),
        NilsList(rows),
      ],
    );
  }
}
