import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';

/// One row of a [NilsList]: a title, a line of detail, badges on the right and, when it can be
/// opened, a chevron.
class NilsRow extends StatelessWidget {
  const NilsRow({
    super.key,
    required this.title,
    this.meta,
    this.badges = const [],
    this.mono = false,
    this.monoMeta = false,
    this.leading,
    this.onTap,
    this.radius = BorderRadius.zero,
  });

  final String title;
  final String? meta;
  final List<Widget> badges;
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
    final phone = ScreenClass.ofContext(context).isPhone;
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
    final tags = badges.isEmpty
        ? null
        : Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: phone ? WrapAlignment.start : WrapAlignment.end,
            children: badges,
          );
    final chevron = onTap == null
        ? null
        : NilsIcon('chevron', size: IconSize.sm, color: t.fade);
    final content = LayoutBuilder(
      builder: (context, box) {
        // The web row wraps its badges under the text when they do not fit beside it.
        final stacked = box.maxWidth < 520 || phone;
        // Beside the text at its natural width, capped so the text keeps room. A Flexible would
        // split the row evenly and push the badges to the middle.
        final beside = stacked || tags == null
            ? null
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth * 0.5),
                child: tags,
              );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Row(
              spacing: 12,
              children: [
                ?leading,
                Expanded(
                  child: Column(
                    spacing: 8,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [body, if (stacked) ?tags],
                  ),
                ),
                ?beside,
                ?chevron,
              ],
            ),
          ),
        );
      },
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
