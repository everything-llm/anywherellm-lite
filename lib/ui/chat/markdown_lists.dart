import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../type.dart';
import '../widgets/controls.dart';

/// A [MarkdownBody] whose tight lists have no space between their items, as a browser draws
/// them. `flutter_markdown_plus` puts `blockSpacing` between every two blocks, a list's items
/// among them, and has no setting for a list's own; this takes that space back out of the
/// widgets it builds. A loose list, whose items hold paragraphs, keeps it.
class TightListMarkdown extends MarkdownBody {
  const TightListMarkdown({
    super.key,
    required super.data,
    super.selectable,
    super.styleSheet,
    super.onTapLink,
    super.imageBuilder,
    super.builders,
    super.extensionSet,
    super.bulletBuilder,
  });

  /// The children as tightened, by the list `flutter_markdown_plus` built, which it hands to
  /// every build until it parses the text again.
  static final _tightened = Expando<List<Widget>>();

  @override
  Widget build(BuildContext context, List<Widget>? children) {
    final spacing = styleSheet?.blockSpacing;
    if (children == null || spacing == null) {
      return super.build(context, children);
    }
    final tight = _tightened[children] ??= [
      for (final child in children) tightenLists(child, spacing),
    ];
    return super.build(context, tight);
  }
}

/// [widget] as `flutter_markdown_plus` built it, with the [spacing] taken out from between the
/// items of each tight list in it and from inside each tight item, which holds a nested list
/// under its text.
Widget tightenLists(Widget widget, double spacing) {
  bool spacer(Widget w) =>
      w is SizedBox &&
      w.width == null &&
      w.child == null &&
      w.height == spacing;
  // An item is a row: its bullet, then its blocks in a Flexible. A tight item's first block is
  // its text, a Wrap; a loose item's is a paragraph, a Column.
  bool tightItem(Widget w) {
    if (w is! Row || w.children.length != 2) return false;
    return switch (w.children[1]) {
      Flexible(child: Column(:final children)) =>
        children.isNotEmpty && children.first is Wrap,
      _ => false,
    };
  }

  switch (widget) {
    case Column(:final children):
      final inner = [for (final c in children) tightenLists(c, spacing)];
      final blocks = inner.where((c) => !spacer(c)).toList();
      final list = blocks.isNotEmpty && blocks.every(tightItem);
      final item = blocks.isNotEmpty && blocks.first is Wrap;
      return Column(
        key: widget.key,
        mainAxisSize: widget.mainAxisSize,
        crossAxisAlignment: widget.crossAxisAlignment,
        children: list || item ? blocks : inner,
      );
    case Row(:final children):
      return Row(
        key: widget.key,
        mainAxisSize: widget.mainAxisSize,
        crossAxisAlignment: widget.crossAxisAlignment,
        textBaseline: widget.textBaseline,
        children: [for (final c in children) tightenLists(c, spacing)],
      );
    case Flexible(:final child, :final fit, :final flex):
      return Flexible(
        key: widget.key,
        fit: fit,
        flex: flex,
        child: tightenLists(child, spacing),
      );
  }
  return widget;
}

/// A list item's bullet: a round dot for an unordered list, as a browser draws it, centred on
/// the item's first line in [style], or the item's number.
Widget listBullet(MarkdownBulletParameters bullet, TextStyle style) {
  if (bullet.style == BulletStyle.orderedList) {
    return Text(
      '${bullet.index + 1}.',
      textAlign: TextAlign.right,
      style: style,
    );
  }
  final size = (style.fontSize ?? Type.chat) / 3;
  final hollow = bullet.nestLevel.isOdd;
  return Text.rich(
    TextSpan(
      // A zero-width space gives the line its height and baseline.
      text: '​',
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hollow ? null : style.color,
              border: hollow ? Border.all(color: style.color!) : null,
            ),
          ),
        ),
      ],
    ),
    textAlign: TextAlign.center,
    style: style,
  );
}

/// The mark an answer still being written ends with, where its [Caret] goes: a character of
/// Unicode's private use area, which no answer holds.
const caretMark = '\uE000';

/// Whether [text], still being written, can take the caret at its end: not while it ends inside
/// a code block or display math, where the mark would show as itself.
bool takesCaret(String text) =>
    _fence.allMatches(text).length.isEven &&
    r'$$'.allMatches(text).length.isEven;

/// A line that opens or closes a code block.
final _fence = RegExp(r'^\s*(```|~~~)', multiLine: true);

/// [caretMark], read as a `caret` element.
class CaretSyntax extends md.InlineSyntax {
  CaretSyntax() : super(caretMark);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('caret'));
    return true;
  }
}

/// Draws a `caret` element as the [Caret], in the line of text it ends, 3 px after its last
/// letter, as the Lite prototype draws a running answer.
class CaretBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => const Text.rich(
    TextSpan(
      children: [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(padding: EdgeInsets.only(left: 3), child: Caret()),
        ),
      ],
    ),
  );
}
