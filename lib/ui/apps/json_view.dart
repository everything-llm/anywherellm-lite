import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/apps.dart';
import '../settings/rows.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/sheet.dart';
import '../widgets/side_scroll.dart';

/// JSON read as a person reads it: each key in the mono face, muted, with a plain value at the
/// row's end, or a nested object or list under it, indented by a rule. A list of plain values
/// is a list of bullets.
class JsonView extends StatelessWidget {
  const JsonView(this.value, {super.key});

  final Object? value;

  @override
  Widget build(BuildContext context) => switch (value) {
    final Map<dynamic, dynamic> map => _entries(context, [
      for (final MapEntry(:key, :value) in map.entries) ('$key', value),
    ]),
    final List<dynamic> list when list.every(_plain) => _bullets(context, list),
    final List<dynamic> list => _entries(context, [
      for (final (i, item) in list.indexed) ('$i', item),
    ]),
    final other => _value(context, other, end: false),
  };

  static bool _plain(Object? value) => value is! Map && value is! List;

  Widget _entries(BuildContext context, List<(String, Object?)> entries) {
    final t = Tokens.of(context);
    if (entries.isEmpty) {
      return Text(
        value is List ? '[]' : '{}',
        style: Type.mono(13, color: t.muted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, (key, child)) in entries.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: i == 0
                ? null
                : BoxDecoration(
                    border: Border(top: BorderSide(color: t.line2)),
                  ),
            child: _plain(child)
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    spacing: 16,
                    children: [
                      Text(key, style: Type.mono(13, color: t.muted)),
                      Expanded(child: _value(context, child, end: true)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 6,
                    children: [
                      Text(key, style: Type.mono(13, color: t.muted)),
                      Container(
                        padding: const EdgeInsets.only(left: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: t.line2, width: 2),
                          ),
                        ),
                        child: JsonView(child),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }

  Widget _bullets(BuildContext context, List<dynamic> list) {
    final t = Tokens.of(context);
    if (list.isEmpty) return Text('[]', style: Type.mono(13, color: t.muted));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        for (final item in list)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: t.ink2,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(child: _value(context, item, end: false)),
            ],
          ),
      ],
    );
  }

  Widget _value(BuildContext context, Object? value, {required bool end}) {
    final t = Tokens.of(context);
    final text = switch (value) {
      null => 'null',
      final String s => s,
      final other => jsonEncode(other),
    };
    return Text(
      text,
      textAlign: end ? TextAlign.end : TextAlign.start,
      style: Type.sans(
        15,
        color: value == null ? t.muted : t.ink,
        height: 1.45,
      ),
    );
  }
}

/// [text] in the mono face with each line's number before it, scrolling sideways rather than
/// wrapping, in a card.
class NumberedText extends StatelessWidget {
  const NumberedText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final lines = const LineSplitter().convert(text);
    final style = Type.mono(13, color: t.ink, height: 1.55);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 0, 6),
      decoration: cardDecoration(t, inSheet: SheetFrame.holds(context)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Text(
              [for (var i = 1; i <= lines.length; i++) '$i'].join('\n'),
              textAlign: TextAlign.end,
              style: style.copyWith(color: t.muted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SideScroll(
              padding: const EdgeInsets.only(right: 16, bottom: 10),
              child: SelectableText(lines.join('\n'), style: style),
            ),
          ),
        ],
      ),
    );
  }
}

/// [lines] in the mono face in a card, each in its own colour, scrolling sideways rather than
/// wrapping: a log line, a state, or a commit's diff.
class CodeBox extends StatelessWidget {
  const CodeBox(this.lines, {super.key});

  /// Plain text, one line.
  CodeBox.text(String text, {Key? key})
    : this([
        for (final line in const LineSplitter().convert(text))
          (DiffKind.context, line),
      ], key: key);

  final List<(DiffKind, String)> lines;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final base = Type.mono(13, color: t.ink, height: 1.55);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 0, 6),
      decoration: cardDecoration(t, inSheet: SheetFrame.holds(context)),
      child: SideScroll(
        padding: const EdgeInsets.only(right: 16, bottom: 10),
        child: SelectableText.rich(
          TextSpan(
            style: base,
            children: [
              for (final (i, (kind, line)) in lines.indexed)
                TextSpan(
                  text: i == lines.length - 1 ? line : '$line\n',
                  style: switch (kind) {
                    DiffKind.header => base.copyWith(color: t.muted),
                    DiffKind.added => base.copyWith(color: t.okfg),
                    DiffKind.removed => base.copyWith(color: t.badfg),
                    DiffKind.context => null,
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A line over a card in an app's data: what is shown on the left, in the mono face, and how
/// much on the right.
class MetaLine extends StatelessWidget {
  const MetaLine(this.what, this.much, {super.key});

  final String what;
  final String much;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final style = Type.mono(13, color: t.muted);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FieldCard.inset,
        4,
        FieldCard.inset,
        12,
      ),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Text(
              what,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          Text(much, style: style),
        ],
      ),
    );
  }
}

/// [child] in a card's padding, as the styled view of a JSON file sits.
class JsonCard extends StatelessWidget {
  const JsonCard(this.child, {super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    decoration: cardDecoration(Tokens.of(context)),
    child: child,
  );
}
