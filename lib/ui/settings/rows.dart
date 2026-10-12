import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/fields.dart';
import '../widgets/tappable.dart';

/// A card's ground: [Tokens.panel], or [Tokens.bg] for a card in a sheet ([inSheet]), with
/// the rounded [Tokens.line2] edge every card has.
BoxDecoration cardDecoration(Tokens t, {bool inSheet = false}) => BoxDecoration(
  color: inSheet ? t.bg : t.panel,
  borderRadius: BorderRadius.circular(Sizes.phoneCard),
  border: Border.all(color: t.line2),
);

/// A rounded panel holding [children] one above another, as Settings draws a card.
class PanelCard extends StatelessWidget {
  const PanelCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.all(FieldCard.inset),
      decoration: cardDecoration(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: children,
      ),
    );
  }
}

/// A rounded panel of [rows], a hairline between each, as a grouped card: its edge is
/// [Tokens.line2] and its hairlines stop [inset] short of its sides, where its rows keep their
/// text. [inSheet] fills it with [Tokens.bg], as a card in a sheet is.
class FieldCard extends StatelessWidget {
  const FieldCard(this.rows, {super.key, this.inSheet = false});

  final List<Widget> rows;
  final bool inSheet;

  /// How far the rows keep their text from the card's sides.
  static const inset = 20.0;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: cardDecoration(t, inSheet: inSheet),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, row) in rows.indexed) Ruled(ruled: i > 0, child: row),
        ],
      ),
    );
  }
}

/// [child] under a hairline [FieldCard.inset] short of its sides when [ruled], as a row of a
/// grouped card under another is. The hairline is drawn over the row's top, inside its height,
/// as a CSS border is.
class Ruled extends StatelessWidget {
  const Ruled({super.key, required this.ruled, required this.child});

  final bool ruled;
  final Widget child;

  @override
  Widget build(BuildContext context) => !ruled
      ? child
      : CustomPaint(
          foregroundPainter: CardHairline(Tokens.of(context).line2),
          child: child,
        );
}

/// A [FieldCard] in a scroll view whose [count] rows are built by [row] as they scroll into
/// view, each keyed by [keyOf] when given, so a row keeps its state as rows come and go.
class SliverFieldCard extends StatelessWidget {
  const SliverFieldCard({
    super.key,
    required this.count,
    required this.row,
    this.keyOf,
    this.inSheet = false,
  });

  final int count;
  final IndexedWidgetBuilder row;
  final Key Function(int i)? keyOf;
  final bool inSheet;

  @override
  Widget build(BuildContext context) {
    const corner = Radius.circular(Sizes.phoneCard - 1);
    final keyOf = this.keyOf;
    return DecoratedSliver(
      decoration: cardDecoration(Tokens.of(context), inSheet: inSheet),
      sliver: SliverPadding(
        // Inside the edge, as a [FieldCard]'s rows are.
        padding: const EdgeInsets.all(1),
        sliver: SliverList.builder(
          itemCount: count,
          findChildIndexCallback: keyOf == null
              ? null
              : (key) {
                  for (var i = 0; i < count; i++) {
                    if (keyOf(i) == key) return i;
                  }
                  return null;
                },
          itemBuilder: (context, i) => ClipRRect(
            key: keyOf?.call(i),
            // The card's corners, clipped from its first and last rows.
            borderRadius: BorderRadius.vertical(
              top: i == 0 ? corner : Radius.zero,
              bottom: i == count - 1 ? corner : Radius.zero,
            ),
            clipBehavior: i == 0 || i == count - 1 ? Clip.antiAlias : Clip.none,
            child: Ruled(ruled: i > 0, child: row(context, i)),
          ),
        ),
      ),
    );
  }
}

/// A line across the top of what it paints over, [FieldCard.inset] short of either side: the
/// rule between two rows of a grouped card.
class CardHairline extends CustomPainter {
  const CardHairline(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(
    Rect.fromLTWH(FieldCard.inset, 0, size.width - 2 * FieldCard.inset, 1),
    Paint()..color = color,
  );

  @override
  bool shouldRepaint(CardHairline old) => old.color != color;
}

/// A setting in a [FieldCard]: its [label] and [help] on the left and its [control] on the
/// right, or the control under them where the row is narrow. A [small] control, such as a
/// switch, stays on the right however narrow, in a 52 px column at the card's inset, in a row
/// as tall as an [InfoRow], as the design canvas draws it.
class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    required this.label,
    required this.control,
    this.help = '',
    this.small = false,
    this.tag,
    this.inSheet = false,
  });

  final String label;
  final String help;
  final Widget control;
  final bool small;

  /// Whether it is a row of a sheet's card, 64 tall rather than a page's.
  final bool inSheet;

  /// A badge beside the label, such as Recommended.
  final Widget? tag;

  /// The least width of a row with its control beside its label rather than under it.
  static const sideBySide = 520.0;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final about = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              label,
              style: Type.sans(
                17,
                weight: inSheet ? FontWeight.w400 : FontWeight.w500,
                color: t.ink,
              ),
            ),
            ?tag,
          ],
        ),
        if (help.isNotEmpty) HelpText(help),
      ],
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: inSheet
            ? 64
            : small
            ? 88
            : 68,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: FieldCard.inset,
          vertical: inSheet ? 6 : 10,
        ),
        child: LayoutBuilder(
          builder: (context, box) => small || box.maxWidth >= sideBySide
              ? Row(
                  spacing: 16,
                  children: [
                    Expanded(child: about),
                    if (small)
                      SizedBox(width: 52, child: Center(child: control))
                    else
                      SizedBox(width: 280, child: control),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [about, control],
                ),
        ),
      ),
    );
  }
}

/// [control] under its [name] in the sans at [size], as a phone's settings set a field or a
/// choice. The name is heard once: as the control's own label when it has one ([labelled]),
/// else as this group's.
class NamedControl extends StatelessWidget {
  const NamedControl(
    this.name,
    this.control, {
    super.key,
    this.size = 15,
    this.labelled = false,
    this.quiet = false,
  });

  final String name;
  final Widget control;
  final double size;
  final bool labelled;

  /// The name small and muted over its field, as a phone's sign-in form sets it.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final named = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        ExcludeSemantics(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: quiet ? 8 : 0),
            child: Text(
              name,
              style: quiet
                  ? Type.sans(13, color: Tokens.of(context).muted)
                  : Type.sans(
                      size,
                      weight: FontWeight.w500,
                      color: Tokens.of(context).ink,
                    ),
            ),
          ),
        ),
        control,
      ],
    );
    if (labelled) return named;
    return Semantics(container: true, label: name, child: named);
  }
}

/// A row of a [FieldCard] that only says something: [title] at 17, with [tag] beside it, over
/// the line [about], in the mono face when [mono], or the line [aboutSpan] drawn as it says, and
/// [trailing] at its end. It is taller
/// than a row that opens something, as the design canvas draws it.
class InfoRow extends StatelessWidget {
  const InfoRow(
    this.title, {
    super.key,
    this.about,
    this.aboutSpan,
    this.mono = false,
    this.tag,
    this.trailing,
  });

  final String title;
  final String? about;
  final InlineSpan? aboutSpan;
  final bool mono;

  /// A badge beside [title], such as Saved.
  final Widget? tag;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.symmetric(
        horizontal: FieldCard.inset,
        vertical: 10,
      ),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  spacing: 10,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: Type.sans(
                          17,
                          weight: FontWeight.w500,
                          color: t.ink,
                        ),
                      ),
                    ),
                    ?tag,
                  ],
                ),
                if (about != null || aboutSpan != null)
                  Text.rich(
                    aboutSpan ?? TextSpan(text: about),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono
                        ? Type.mono(13, color: t.muted)
                        : Type.sans(13, color: t.muted),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A row that only shows a [value], right-aligned, beside its [label].
class ReadOnlyRow extends StatelessWidget {
  const ReadOnlyRow({
    super.key,
    required this.label,
    required this.value,
    this.help = '',
  });

  final String label;
  final String value;
  final String help;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return FieldRow(
      label: label,
      help: help,
      control: Text(
        value,
        textAlign: TextAlign.end,
        style: Type.sans(13.5, color: t.ink2, height: 1.45),
      ),
    );
  }
}

/// A section's heading inside a page, in the sans face.
class SubHead extends StatelessWidget {
  const SubHead(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Semantics(
      header: true,
      child: Text(
        title,
        style: Type.sans(
          17,
          weight: FontWeight.w600,
          color: Tokens.of(context).ink,
        ),
      ),
    ),
  );
}

/// A line of muted text between a page's cards.
class PageNote extends StatelessWidget {
  const PageNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Text(text, style: Type.sans(13.5, color: t.muted, height: 1.55));
  }
}

/// A warning between a page's cards, on the warning ground.
class PageWarning extends StatelessWidget {
  const PageWarning(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.warnbg,
        borderRadius: BorderRadius.circular(Sizes.phoneCard),
      ),
      child: Text(text, style: Type.sans(14, color: t.warnfg, height: 1.5)),
    );
  }
}

/// A button that opens or closes what is under it: a chevron that turns, then [label]. Heard as
/// expanded or collapsed.
class Fold extends StatelessWidget {
  const Fold({
    super.key,
    required this.label,
    required this.open,
    required this.onToggle,
  });

  final String label;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Tappable(
        label: label,
        expanded: open,
        onTap: onToggle,
        radius: BorderRadius.circular(8),
        child: SizedBox(
          height: 36,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              RotatedBox(
                quarterTurns: open ? 1 : 0,
                child: AppIcon('chevron', size: IconSize.xs, color: t.ink2),
              ),
              Text(
                label,
                style: Type.sans(14, weight: FontWeight.w500, color: t.ink2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How a [CardRow]'s words are drawn: as text, as an action in the accent, or as a destructive
/// action in [Tokens.badfg].
enum RowTone { plain, accent, danger }

/// A row of a phone's [FieldCard] that does one thing when tapped: [icon] at 22, then [label]
/// at 17 in its [tone], then [trailing], kept [FieldCard.inset] from the card's sides. A
/// [large] row is a page's, as tall as a [NavRow] with its icon at 24.
class CardRow extends StatelessWidget {
  const CardRow(
    this.label, {
    super.key,
    required this.onTap,
    this.icon,
    this.trailing,
    this.tone = RowTone.plain,
    this.strong = false,
    this.height = 64,
    this.large = false,
    this.checked,
    this.heard,
  });

  final String label;

  /// What a screen reader hears in place of [label], when it says more.
  final String? heard;

  /// Null while the row can do nothing, which fades it.
  final VoidCallback? onTap;
  final String? icon;
  final Widget? trailing;
  final RowTone tone;

  /// Semibold words, as New workspace is.
  final bool strong;
  final double height;
  final bool large;

  /// For a row that is one of a choice: whether it is the one chosen, which a check before it
  /// marks and its words in semibold, and a screen reader hears.
  final bool? checked;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final color = switch (tone) {
      RowTone.plain => t.ink,
      RowTone.accent => t.accent,
      RowTone.danger => t.badfg,
    };
    return Tappable(
      label: heard ?? label,
      selected: checked,
      onTap: onTap,
      dimWhenDisabled: 0.5,
      child: Container(
        constraints: BoxConstraints(minHeight: large ? 68 : height),
        padding: const EdgeInsets.symmetric(horizontal: FieldCard.inset),
        child: Row(
          spacing: large ? 16 : 14,
          children: [
            if (checked case final checked?)
              SizedBox.square(
                dimension: IconSize.row.px,
                child: checked
                    ? AppIcon('check', size: IconSize.row, color: color)
                    : null,
              )
            else if (icon case final icon?)
              AppIcon(
                icon,
                size: large ? IconSize.large : IconSize.row,
                color: color,
              ),
            Expanded(
              child: Text(
                label,
                style: Type.sans(
                  17,
                  weight: strong || checked == true
                      ? FontWeight.w600
                      : tone == RowTone.accent || large
                      ? FontWeight.w500
                      : FontWeight.w400,
                  color: color,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// A card that sums one thing up, as Settings' server and the workspace are: [title] at 19,
/// with [trailing] at its end, the [lines] under it, then [link], a row in the accent over a
/// hairline, which does [onLink].
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.title,
    this.trailing,
    this.lines = const [],
    this.link,
    this.onLink,
  });

  final String title;
  final Widget? trailing;
  final List<Widget> lines;
  final String? link;

  /// Null while the link can do nothing, which fades it.
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.all(FieldCard.inset),
      decoration: cardDecoration(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: 12,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sans(19, weight: FontWeight.w500, color: t.ink),
                ),
              ),
              ?trailing,
            ],
          ),
          ...lines,
          if (link case final link?)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Tappable(
                label: link,
                onTap: onLink,
                dimWhenDisabled: 0.5,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.only(top: 6),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.line2)),
                  ),
                  child: Text(
                    link,
                    style: Type.sans(
                      17,
                      weight: FontWeight.w500,
                      color: t.accent,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A heading over a phone's [FieldCard], its words in line with the card's rows, [top] under
/// what is above it and 10 over the card.
class CardHeading extends StatelessWidget {
  const CardHeading(this.text, {super.key, this.top = 20});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(FieldCard.inset, top, FieldCard.inset, 10),
    child: SectionLabel(text),
  );
}

/// A muted line in a [FieldCard], where its rows would be, as when there are none.
class CardNote extends StatelessWidget {
  const CardNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 64),
    padding: const EdgeInsets.symmetric(
      horizontal: FieldCard.inset,
      vertical: 12,
    ),
    alignment: Alignment.centerLeft,
    child: Text(text, style: Type.sans(15.5, color: Tokens.of(context).muted)),
  );
}
