import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';
import '../widgets/sheet.dart';
import '../widgets/tappable.dart';

/// A card: a [Tokens.tile] floating on the tile's shadow inside its [Tokens.tileEdge], which
/// only the increased-contrast themes draw; or, in a sheet ([inSheet]), a flat [Tokens.ground]
/// well inside a [Tokens.line] edge.
BoxDecoration cardDecoration(Tokens t, {bool inSheet = false}) => BoxDecoration(
  color: inSheet ? t.ground : t.tile,
  borderRadius: BorderRadius.circular(Sizes.card),
  border: Border.all(color: inSheet ? t.line : t.tileEdge),
  boxShadow: inSheet ? null : t.tileShadow,
);

/// A rounded panel holding [children] one above another, [spacing] apart, as Settings draws a
/// card.
class PanelCard extends StatelessWidget {
  const PanelCard({super.key, required this.children, this.spacing = 10});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.all(FieldCard.inset),
      decoration: cardDecoration(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: spacing,
        children: children,
      ),
    );
  }
}

/// A small line of words in line with a [CardHeading] and the text of a card's rows, which is
/// [FieldCard.inset] in from the card's sides.
class CardCaption extends StatelessWidget {
  const CardCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: FieldCard.inset),
    child: Text(text, style: Type.note(Tokens.of(context).ink)),
  );
}

/// A rounded panel of [rows], a hairline between each, as a grouped card: a [cardDecoration],
/// whose hairlines stop [inset] short of its sides, where its rows keep their
/// text. In a [SheetFrame] it is filled with [Tokens.ground], as a card in a sheet is.
class FieldCard extends StatelessWidget {
  const FieldCard(this.rows, {super.key, this.ruledAt});

  final List<Widget> rows;

  /// Whether the row at an index has a hairline over it, when not every row but the first has,
  /// as a row under a heading of its own has none.
  final bool Function(int i)? ruledAt;

  /// How far the rows keep their text from the card's sides.
  static const inset = 20.0;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: cardDecoration(t, inSheet: SheetFrame.holds(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, row) in rows.indexed)
            Ruled(ruled: ruledAt?.call(i) ?? i > 0, child: row),
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
          foregroundPainter: CardHairline(Tokens.of(context).line),
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
    this.ruledAt,
  });

  final int count;
  final IndexedWidgetBuilder row;
  final Key Function(int i)? keyOf;

  /// As [FieldCard.ruledAt].
  final bool Function(int i)? ruledAt;

  @override
  Widget build(BuildContext context) {
    const corner = Radius.circular(Sizes.card - 1);
    final keyOf = this.keyOf;
    return DecoratedSliver(
      decoration: cardDecoration(
        Tokens.of(context),
        inSheet: SheetFrame.holds(context),
      ),
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
            child: Ruled(
              ruled: ruledAt?.call(i) ?? i > 0,
              child: row(context, i),
            ),
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
/// as tall as an [InfoRow], as the Lite prototype draws it.
class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    required this.label,
    required this.control,
    this.help = '',
    this.small = false,
  });

  /// A small row of [label] over the line [help] with a switch, which a screen reader hears as
  /// [switchLabel], or as [label] when there is none. The switch is off the page's reach while
  /// [onChanged] is null.
  factory FieldRow.toggle({
    Key? key,
    required String label,
    required bool value,
    required ValueChanged<bool>? onChanged,
    String help = '',
    String? switchLabel,
  }) => FieldRow(
    key: key,
    label: label,
    help: help,
    small: true,
    control: AppSwitch(
      value: value,
      label: switchLabel ?? label,
      onChanged: onChanged,
    ),
  );

  final String label;
  final String help;
  final Widget control;
  final bool small;

  /// The least width of a row with its control beside its label rather than under it.
  static const sideBySide = 520.0;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    // A row of a sheet's card is 64 tall rather than a page's.
    final inSheet = SheetFrame.holds(context);
    final about = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Type.body(t.ink)),
        if (help.isNotEmpty) HelpText(help),
      ],
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: inSheet ? Sizes.cardRow : Sizes.pageRow,
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

/// [control] under its [name] as [Type.body], or small at 13 when [quiet], as a phone's
/// settings set a field or a choice. The name is heard once: as the control's own label when it has one ([labelled]),
/// else as this group's.
class NamedControl extends StatelessWidget {
  const NamedControl(
    this.name,
    this.control, {
    super.key,
    this.labelled = false,
    this.quiet = false,
  });

  final String name;
  final Widget control;
  final bool labelled;

  /// The name small over its field, as a phone's sign-in form sets it.
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
                  ? Type.note(Tokens.of(context).ink)
                  : Type.body(Tokens.of(context).ink),
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

/// A row of a [FieldCard] that only says something: [title] as [Type.body], with [tag] beside it, over
/// the line [about], in the mono face when [mono], or the line [aboutSpan] drawn as it says. It
/// is as tall as a row that opens something, or a sheet's row in a sheet.
class InfoRow extends StatelessWidget {
  const InfoRow(
    this.title, {
    super.key,
    this.about,
    this.aboutSpan,
    this.aboutLines = 1,
    this.mono = false,
    this.tag,
  });

  final String title;
  final String? about;
  final InlineSpan? aboutSpan;

  /// How many lines the line under the title may take before it is cut short. A [mono] line is
  /// an address and shows whole, on as many lines as it takes: cut short,
  /// `https://home.ts.net.evil.example` would read as the person's own server.
  final int aboutLines;
  final bool mono;

  /// A badge beside [title], such as Saved.
  final Widget? tag;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      constraints: BoxConstraints(
        minHeight: SheetFrame.holds(context) ? Sizes.cardRow : Sizes.pageRow,
      ),
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
                    Flexible(child: Text(title, style: Type.body(t.ink))),
                    ?tag,
                  ],
                ),
                if (about != null || aboutSpan != null)
                  Text.rich(
                    aboutSpan ?? TextSpan(text: about),
                    maxLines: mono ? null : aboutLines,
                    overflow: mono ? null : TextOverflow.ellipsis,
                    style: mono
                        ? Type.mono(13, color: t.ink, height: 1.4)
                        : Type.note(t.ink),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A row that only shows a [value] under its [label], left-aligned with the rows around it,
/// which may take up to four lines.
class ReadOnlyRow extends StatelessWidget {
  const ReadOnlyRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) =>
      InfoRow(label, about: value, aboutLines: 4);
}

/// A sentence between a page's cards, as running text: [Type.body] in ink.
class PageNote extends StatelessWidget {
  const PageNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Text(text, style: Type.body(t.ink));
  }
}

/// How a [CardRow]'s words are drawn: as text, as an action in the accent, or as a destructive
/// action in [Tokens.danger].
enum RowTone { plain, accent, danger }

/// A row of a phone's [FieldCard] that does one thing when tapped: [icon] at 22, then [label]
/// as [Type.body] in its [tone], then [trailing], kept [FieldCard.inset] from the card's sides. A
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
    this.large = false,
    this.checked,
    this.heard,
    this.maxLines,
  });

  final String label;

  /// The most lines [label] may take, ending in an ellipsis past them, or null for as many as it
  /// needs.
  final int? maxLines;

  /// What a screen reader hears in place of [label], when it says more.
  final String? heard;

  /// Null while the row can do nothing, which fades it.
  final VoidCallback? onTap;
  final String? icon;
  final Widget? trailing;
  final RowTone tone;

  /// Semibold words, as New workspace is.
  final bool strong;
  final bool large;

  /// For a row that is one of a choice: whether it is the one chosen, which a check before it
  /// marks and its words in semibold, and a screen reader hears.
  final bool? checked;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    // Disabled, its words and icon are muted, opaque.
    final color = onTap == null
        ? t.muted
        : switch (tone) {
            RowTone.plain => t.ink,
            RowTone.accent => t.accent,
            RowTone.danger => t.danger,
          };
    return Tappable(
      label: heard ?? label,
      selected: checked,
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(
          minHeight: large ? Sizes.pageRow : Sizes.cardRow,
        ),
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
                maxLines: maxLines,
                overflow: maxLines == null ? null : TextOverflow.ellipsis,
                style: Type.body(
                  color,
                  weight: strong || checked == true || tone == RowTone.accent
                      ? FontWeight.w600
                      : FontWeight.w400,
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

/// A card that sums one thing up, as Settings' server and the workspace are: [title] as [Type.title],
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
    this.action,
  });

  final String title;
  final Widget? trailing;
  final List<Widget> lines;

  /// A button under [lines], such as the primary one the card exists for.
  final Widget? action;
  final String? link;

  /// Null while the link can do nothing, which fades it.
  final VoidCallback? onLink;

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
            // Less under the lines when a link follows, which has its own room.
            padding: EdgeInsets.fromLTRB(
              FieldCard.inset,
              FieldCard.inset,
              FieldCard.inset,
              link == null ? FieldCard.inset : 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                LayoutBuilder(
                  builder: (context, box) => Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    spacing: 12,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Type.title(t.ink),
                        ),
                      ),
                      // At the card's end, and no wider than half of it, so it gives way to the
                      // title on a narrow card with large text.
                      if (trailing case final trailing?)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: box.maxWidth / 2,
                          ),
                          child: trailing,
                        ),
                    ],
                  ),
                ),
                ...lines,
                if (action case final action?) ...[
                  const SizedBox(height: 4),
                  action,
                ],
              ],
            ),
          ),
          if (link case final link?)
            Ruled(
              ruled: true,
              child: Tappable(
                label: link,
                onTap: onLink,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(
                    horizontal: FieldCard.inset,
                  ),
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    link,
                    style: Type.label(onLink == null ? t.muted : t.accent),
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
    constraints: const BoxConstraints(minHeight: Sizes.cardRow),
    padding: const EdgeInsets.symmetric(
      horizontal: FieldCard.inset,
      vertical: 12,
    ),
    alignment: Alignment.centerLeft,
    child: Text(text, style: Type.body(Tokens.of(context).muted)),
  );
}

/// Words in a [FieldCard], wrapped, in [color] or else [Tokens.ink], such as what a task asks.
class CardWords extends StatelessWidget {
  const CardWords(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: FieldCard.inset,
      vertical: 16,
    ),
    child: Text(text, style: Type.body(color ?? Tokens.of(context).ink)),
  );
}

/// A label over a card in a sheet, such as Recent runs, in from the card's edge.
class SheetLabel extends StatelessWidget {
  const SheetLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: SectionLabel(text, header: false),
  );
}
