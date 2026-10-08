import 'package:flutter/material.dart';

import '../tokens.dart';
import '../type.dart';
import '../widgets/fields.dart';

/// A rounded panel holding [children] one above another, as Settings draws a card.
class PanelCard extends StatelessWidget {
  const PanelCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: children,
      ),
    );
  }
}

/// A rounded panel of [rows], a hairline between each.
class FieldCard extends StatelessWidget {
  const FieldCard(this.rows, {super.key});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: t.line2),
            row,
          ],
        ],
      ),
    );
  }
}

/// A setting in a [FieldCard]: its [label] and [help] on the left and its [control] on the
/// right, or the control under them where the row is narrow. A [small] control, such as a
/// switch, stays on the right however narrow.
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
    final about = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              label,
              style: Type.sans(14.5, weight: FontWeight.w500, color: t.ink),
            ),
            ?tag,
          ],
        ),
        if (help.isNotEmpty) HelpText(help),
      ],
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: LayoutBuilder(
          builder: (context, box) => small || box.maxWidth >= sideBySide
              ? Row(
                  spacing: small ? 12 : 16,
                  children: [
                    Expanded(child: about),
                    if (small)
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
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(text, style: Type.sans(14, color: t.warnfg, height: 1.5)),
    );
  }
}
