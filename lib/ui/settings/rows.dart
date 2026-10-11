import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/fields.dart';
import '../widgets/tappable.dart';

/// A rounded panel holding [children] one above another, as Settings draws a card.
class PanelCard extends StatelessWidget {
  const PanelCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final phone = ScreenClass.ofContext(context).isPhone;
    return Container(
      padding: phone
          ? const EdgeInsets.all(FieldCard.inset)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(Sizes.cardOf(context)),
        border: Border.all(color: phone ? t.line2 : t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: children,
      ),
    );
  }
}

/// A rounded panel of [rows], a hairline between each. On a phone it is a grouped card: its
/// edge is [Tokens.line2] and its hairlines stop [inset] short of its sides, where its rows keep
/// their text. [inSheet] fills it with [Tokens.bg], as a card in a sheet is.
class FieldCard extends StatelessWidget {
  const FieldCard(this.rows, {super.key, this.inSheet = false});

  final List<Widget> rows;
  final bool inSheet;

  /// How far a phone's rows keep their text from the card's sides.
  static const inset = 20.0;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final phone = ScreenClass.ofContext(context).isPhone;
    final indent = phone ? inset : 0.0;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: inSheet ? t.bg : t.panel,
        borderRadius: BorderRadius.circular(Sizes.cardOf(context)),
        border: Border.all(color: phone ? t.line2 : t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: indent,
                endIndent: indent,
                color: t.line2,
              ),
            row,
          ],
        ],
      ),
    );
  }
}

/// A setting in a [FieldCard]: its [label] and [help] on the left and its [control] on the
/// right, or the control under them where the row is narrow. A [small] control, such as a
/// switch, stays on the right however narrow; on a phone it sits in a 52 px column near the
/// card's edge, as the design canvas draws it.
class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    required this.label,
    required this.control,
    this.help = '',
    this.small = false,
    this.tag,
  });

  final String label;
  final String help;
  final Widget control;
  final bool small;

  /// A badge beside the label, such as Recommended.
  final Widget? tag;

  /// The least width of a row with its control beside its label rather than under it.
  static const sideBySide = 520.0;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final phone = ScreenClass.ofContext(context).isPhone;
    final about = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: phone ? 0 : 2,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              label,
              style: Type.sans(
                phone ? 17 : 14.5,
                weight: FontWeight.w500,
                color: t.ink,
              ),
            ),
            ?tag,
          ],
        ),
        if (help.isNotEmpty) HelpText(help),
      ],
    );
    final edge = phone && small;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: phone ? 68 : 56),
      child: Padding(
        padding: edge
            ? const EdgeInsets.fromLTRB(FieldCard.inset, 6, 4, 6)
            : EdgeInsets.symmetric(
                horizontal: phone ? FieldCard.inset : 16,
                vertical: 10,
              ),
        child: LayoutBuilder(
          builder: (context, box) => small || box.maxWidth >= sideBySide
              ? Row(
                  spacing: edge ? 8 : (small ? 12 : 16),
                  children: [
                    Expanded(child: about),
                    if (edge)
                      SizedBox(width: 52, child: Center(child: control))
                    else if (small)
                      control
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
        borderRadius: BorderRadius.circular(Sizes.cardOf(context)),
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

/// A row of a phone's [FieldCard] that does one thing when tapped: [icon], then [label] at 17
/// in its [tone], then [trailing], kept [FieldCard.inset] from the card's sides.
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
  });

  final String label;

  /// Null while the row can do nothing, which fades it.
  final VoidCallback? onTap;
  final String? icon;
  final Widget? trailing;
  final RowTone tone;

  /// Semibold words, as New workspace is.
  final bool strong;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final color = switch (tone) {
      RowTone.plain => t.ink,
      RowTone.accent => t.accent,
      RowTone.danger => t.badfg,
    };
    return Tappable(
      label: label,
      onTap: onTap,
      dimWhenDisabled: 0.5,
      child: Container(
        constraints: BoxConstraints(minHeight: height),
        padding: const EdgeInsets.symmetric(horizontal: FieldCard.inset),
        child: Row(
          spacing: 16,
          children: [
            if (icon case final icon?)
              AppIcon(icon, color: tone == RowTone.plain ? t.ink2 : color),
            Expanded(
              child: Text(
                label,
                style: Type.sans(
                  17,
                  weight: strong
                      ? FontWeight.w600
                      : tone == RowTone.accent
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

/// A heading over a phone's [FieldCard], its words in line with the card's rows.
class CardHeading extends StatelessWidget {
  const CardHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: FieldCard.inset),
    child: SectionLabel(text),
  );
}
